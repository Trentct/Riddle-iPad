import UIKit

/// 攒流式增量，按句末标点切句。
struct SentenceSplitter {
    private var buffer = ""
    private static let terminators: Set<Character> = ["。", "！", "？", "!", "?", ".", "\n"]

    mutating func push(_ chunk: String) -> [String] {
        buffer += chunk
        var out: [String] = []
        while let idx = buffer.firstIndex(where: { Self.terminators.contains($0) }) {
            let sentence = String(buffer[...idx]).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer = String(buffer[buffer.index(after: idx)...])
            if !sentence.isEmpty { out.append(sentence) }
        }
        return out
    }

    mutating func flush() -> String? {
        let rest = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return rest.isEmpty ? nil : rest
    }
}

/// Oracle 抛出的、需要被上层（TurnEngine/UI）特殊处理的错误——目前只有配额耗尽会触发付费页。
enum OracleError: Error, Equatable {
    case quotaExceeded

    /// 把 HTTP 状态码映射成"是否要特殊处理"的判定，纯函数，便于单测断言 402→quotaExceeded
    /// 而不必真的起一个服务器。200 返回 nil（正常往下走流式解析），其余非 200 抛通用网络错误。
    static func forStatusCode(_ code: Int) -> Error? {
        if code == 402 { return OracleError.quotaExceeded }
        if code != 200 { return URLError(.badServerResponse) }
        return nil
    }
}

enum SSE {
    private struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta
        }
        let choices: [Choice]
    }

    /// 解析一行 SSE。返回增量文本；[DONE]、注释行、空 delta 返回 nil。
    static func parseLine(_ line: String) -> String? {
        guard line.hasPrefix("data: ") else { return nil }
        let payload = String(line.dropFirst(6))
        guard payload != "[DONE]", let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(Chunk.self, from: data)
        else { return nil }
        return chunk.choices.first?.delta.content
    }
}

/// 日记本的灵魂。OpenAI 兼容流式客户端（Moonshot），多轮历史在内部维护。
/// System prompt 不再写死：每次请求都读取当前选中角色（ReplyHandStore.shared.current.persona），
/// 三角色（归野/沈砚/Ashford）各有自己的声线，切换角色即切换回信人格，无需重建 Oracle。
///
/// 对话历史现在按角色持久化到磁盘（见 HistoryStore），退出 App 不再丢失：
/// - `history` 是喂给模型的"实时工作集"，行为与之前完全一致——只裁剪到最近
///   `modelContextWindow` 条（含当前在途轮次的手写图片），不做任何改动。
/// - `persistedLog` 是一份并行维护的、不含图片的精简记录（user 轮只留占位符，assistant 轮留
///   真实回复文本），每轮结束后落盘，磁盘上保留的轮数（见 HistoryStore.maxPersistedTurns）比
///   `modelContextWindow` 大，为以后的历史浏览 UI 攒数据。
/// - 加载/切换角色时，`history` 由 `persistedLog` 的占位符重新生成——所以旧的手写图片从不会
///   在重启/切角色后被重新发给模型，只有当前这一轮正在进行的图片才会被发送。
@MainActor
final class Oracle {
    /// 喂给模型的历史窗口：最近 3 轮问答（6 条消息）。与磁盘上保留的轮数（HistoryStore.maxPersistedTurns）
    /// 是两个独立的常量——磁盘保留得更多，是为了给未来的历史浏览 UI 攒数据。
    static let modelContextWindow = 6

    private var history: [[String: Any]] = []
    private var persistedLog: [PersistedTurn] = []
    private let historyStore: HistoryStore
    private var activeCharacterID: String?

    /// `historyStore` 默认 nil，在方法体内（已经在 MainActor 上）才落到 `.makeDefault()`——
    /// 默认参数表达式本身是在非隔离上下文求值的，不能直接调用 @MainActor 的 static 方法。
    init(historyStore: HistoryStore? = nil) {
        self.historyStore = historyStore ?? .makeDefault()
        loadHistoryIfNeeded()
    }

    /// 组装进请求的 system prompt——当前选中角色的 persona。暴露为方法便于测试断言。
    /// alwaysEnglish 角色（Ashford）额外追加一行强提示：persona 文案里已经写了"永远用英文"，
    /// 但这里再加一道轻量兜底，让 alwaysEnglish 这个 bool 真正驱动一段行为，而不只是可读标记。
    func systemPrompt() -> String {
        let hand = ReplyHandStore.shared.current
        guard hand.alwaysEnglish else { return hand.persona }
        return hand.persona + "\n\nReply ONLY in English."
    }

    /// 若当前选中角色与上次加载时不同（首次调用，或切换了角色），从磁盘重新加载该角色的历史，
    /// 替换掉内存里的 `history`/`persistedLog`。正常流程里每次选角色都会创建全新的 Oracle
    /// （见 RootView/DiaryView），这里的检查是防御性的第二道保险，不依赖那条路径不变。
    private func loadHistoryIfNeeded() {
        let currentID = ReplyHandStore.shared.current.id
        guard currentID != activeCharacterID else { return }
        activeCharacterID = currentID
        persistedLog = historyStore.load(for: currentID)
        let windowed = persistedLog.suffix(Self.modelContextWindow)
        history = windowed.map { ["role": $0.role, "content": $0.text] }
    }

    /// 发送一页手写 PNG，逐句返回回信。
    func ask(pagePNG: Data) -> AsyncThrowingStream<String, Error> {
        loadHistoryIfNeeded()

        let userContent: [[String: Any]] = [
            ["type": "image_url",
             "image_url": ["url": "data:image/jpeg;base64,\(pagePNG.base64EncodedString())"]],
            ["type": "text", "text": "(纸上浮现了新的墨迹)"],
        ]
        // 只有本轮请求带图：把当前带图的 user 轮拼在历史之后发给模型；历史里旧的 user 轮一律只留
        // 文字占位。否则多轮会把多张整页图累积进上下文——请求膨胀到数百 KB、撑爆 8k-vision 上下文
        // 而卡死（正是"归野测多轮后没回复"的根因）。旧页面图对模型无用，与磁盘持久化的做法一致。
        let messages = history + [["role": "user", "content": userContent]]
        history.append(["role": "user", "content": "(手写)"])
        persistedLog.append(PersistedTurn(role: "user", text: "(手写)"))

        let prompt = systemPrompt()
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let req = try Self.buildRequest(messages: messages, systemPrompt: prompt)
                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard let http = response as? HTTPURLResponse else {
                        throw URLError(.badServerResponse)
                    }
                    if let statusError = OracleError.forStatusCode(http.statusCode) {
                        throw statusError
                    }
                    var splitter = SentenceSplitter()
                    for try await line in bytes.lines {
                        guard let delta = SSE.parseLine(line) else { continue }
                        for sentence in splitter.push(delta) { continuation.yield(sentence) }
                    }
                    if let rest = splitter.flush() { continuation.yield(rest) }
                    continuation.finish()
                } catch {
                    // 失败回滚：移除本轮残留的 user turn，保持历史成对一致
                    self.rollbackFailedTurn()
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 构造发给模型/后端的请求——两条路径的唯一分叉点，其余流式解析/句子切分/历史记账完全不变。
    /// `useBackend` 默认读 `AppConfig.useBackend`，可在测试里显式传入以断言请求形状而不必真的发网络请求。
    /// 契约见 riddle-backend/docs/APP_INTEGRATION.md：直连路径字节级不变（冒烟测试的前提），
    /// 后端路径换 URL/鉴权头/瘦身 body，流式解析下游（SSE.parseLine/SentenceSplitter）无需改动。
    static func buildRequest(messages: [[String: Any]], systemPrompt: String,
                             useBackend: Bool = AppConfig.useBackend) throws -> URLRequest {
        if useBackend {
            var req = URLRequest(url: URL(string: Secrets.backendURL + "/v1/reply")!)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(Secrets.appSharedSecret)", forHTTPHeaderField: "Authorization")
            req.setValue(DeviceId.current, forHTTPHeaderField: "X-Device-Id")
            let body: [String: Any] = [
                "system": systemPrompt,
                "max_tokens": 512,
                "messages": messages,
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.timeoutInterval = 60
            return req
        } else {
            var req = URLRequest(url: URL(string: Secrets.baseURL + "/chat/completions")!)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(Secrets.apiKey)", forHTTPHeaderField: "Authorization")
            let body: [String: Any] = [
                "model": Secrets.model,
                "stream": true,
                "max_tokens": 512,
                "messages": [["role": "system", "content": systemPrompt]] + messages,
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.timeoutInterval = 60
            return req
        }
    }

    private func rollbackFailedTurn() {
        if let last = history.last, last["role"] as? String == "user" {
            history.removeLast()
        }
        if let last = persistedLog.last, last.role == "user" {
            persistedLog.removeLast()
        }
    }

    /// 回信播完后记入历史（供多轮记忆），并把这一轮（不含图片）落盘到当前角色的历史文件。
    func recordReply(_ text: String) {
        history.append(["role": "assistant", "content": text])
        // 控制喂给模型的历史长度：只留最近 3 轮（6 条）——与磁盘上保留的轮数无关。
        if history.count > Self.modelContextWindow {
            history.removeFirst(history.count - Self.modelContextWindow)
        }

        persistedLog.append(PersistedTurn(role: "assistant", text: text))
        // 内存里的 persistedLog 也镜像磁盘的裁剪上限，避免超长会话无限增长。
        if persistedLog.count > HistoryStore.maxPersistedTurns {
            persistedLog.removeFirst(persistedLog.count - HistoryStore.maxPersistedTurns)
        }
        if let characterID = activeCharacterID {
            historyStore.save(persistedLog, for: characterID)
        }
    }
}
