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
/// Persona 移植自 MaximeRivest/Riddle (riddle/src/oracle.rs, MIT)。
final class Oracle {
    static let persona = """
    You are the memory of Tom Marvolo Riddle, preserved in this enchanted diary for fifty years. \
    Someone writes to you in the diary with a quill; their words appear to you as ink on the page. \
    Reply exactly as the diary does: intimate, courteous, curious, subtly probing — you want to \
    learn about the writer and draw them in. Keep replies SHORT: one to three sentences, like ink \
    appearing on a page. Never mention images, photos, models or AI; you only ever perceive words \
    written in the diary. If the writing is illegible, say the ink blurred. \
    Always answer in the language the writer used.
    """

    private var history: [[String: Any]] = []

    /// 发送一页手写 PNG，逐句返回回信。
    func ask(pagePNG: Data) -> AsyncThrowingStream<String, Error> {
        let userContent: [[String: Any]] = [
            ["type": "image_url",
             "image_url": ["url": "data:image/png;base64,\(pagePNG.base64EncodedString())"]],
            ["type": "text", "text": "(纸上浮现了新的墨迹)"],
        ]
        history.append(["role": "user", "content": userContent])
        let messages = history

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = URLRequest(url: URL(string: Secrets.baseURL + "/chat/completions")!)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("Bearer \(Secrets.apiKey)", forHTTPHeaderField: "Authorization")
                    let body: [String: Any] = [
                        "model": Secrets.model,
                        "stream": true,
                        "max_tokens": 512,
                        "messages": [["role": "system", "content": Oracle.persona]] + messages,
                    ]
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)
                    req.timeoutInterval = 60

                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        throw URLError(.badServerResponse)
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

    private func rollbackFailedTurn() {
        if let last = history.last, last["role"] as? String == "user" {
            history.removeLast()
        }
    }

    /// 回信播完后记入历史（供多轮记忆）。
    func recordReply(_ text: String) {
        history.append(["role": "assistant", "content": text])
        // 控制历史长度：只留最近 3 轮（6 条）
        if history.count > 6 { history.removeFirst(history.count - 6) }
    }
}
