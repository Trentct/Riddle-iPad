import Foundation

/// 单条持久化的历史轮次——不含图片，只有轻量文本。
/// user 轮：手写页面图片只在当轮回合内有意义（发给模型看这一页写了什么），体积大且我们也没有
/// OCR/识别后的文字可存，所以落盘时只留一个占位符，标记"这个位置用户写过字"。
/// assistant 轮：保留真实回复文本——这是我们本来就有的数据，也是未来历史浏览 UI 真正想展示的内容。
struct PersistedTurn: Codable, Equatable {
    let role: String   // "user" | "assistant"
    let text: String
}

/// 按角色 id 把对话历史持久化到磁盘，退出 App 不再丢失。
///
/// 设计取舍（写在这里而不是散落在调用点，方便以后改动前先看一眼）：
/// - **不存图片**：磁盘上的 user 轮只有占位符文本（如"(手写)"），从不写入 base64 图片数据。
///   这意味着重启/切角色重新加载历史后，模型看到的上下文是"助手之前回复过什么 + 用户在这些位置
///   写过字"，而不是完整的多模态历史——旧的手写页面画面不会被重新发给模型。只有当前这一轮
///   正在进行中的图片才会被发送。这是本期最小实现刻意接受的局限：真正有价值的是「对话没消失」，
///   而不是「模型记得每一页写了什么」。
/// - **每个角色一个文件**（history/<characterId>.json），而不是一个大 JSON 里按 key 存所有角色：
///   心智模型更简单，且任一角色的文件损坏只影响它自己，不会拖累其它角色的历史。
/// - **磁盘上保留的轮数 > 喂给模型的轮数**：这里最多保留 `maxPersistedTurns`（20）轮，供以后做
///   历史浏览 UI；Oracle 实际拼进请求的窗口要小得多（见 Oracle 里的模型上下文窗口常量），
///   两者是两件事，不需要相等。
/// - **原子写**：先写临时文件，再用 `moveItem` 完成"重命名"落地，避免写到一半被杀进程/崩溃时
///   把 JSON 文件写成半截、下次加载直接损坏。
/// - **同步文件 I/O**：历史文本不含图片，体积很小（几十到几百 KB 封顶），在 MainActor 上同步
///   读写足够快，不值得为此引入 Task.detached / 后台队列的复杂度。
/// - **绝不因为存储层的问题崩溃**：加载时文件缺失、内容损坏、JSON 解码失败，一律安静地返回空
///   历史；保存失败（磁盘满、权限问题等）也只是静默放弃这一次落盘，不影响当前会话内存里的状态。
@MainActor
final class HistoryStore {
    /// 磁盘上每个角色最多保留的轮次数——比 Oracle 实际喂给模型的窗口大，专为未来的历史浏览 UI 预留。
    static let maxPersistedTurns = 20

    private let baseDirectory: URL
    private let fileManager: FileManager

    /// - Parameters:
    ///   - baseDirectory: 历史文件的根目录，实际文件落在 `<baseDirectory>/history/<characterId>.json`。
    ///     生产环境传 Application Support 目录；单元测试传注入的临时目录，避免碰真实沙盒。
    ///   - fileManager: 便于测试注入；默认 `.default`。
    init(baseDirectory: URL, fileManager: FileManager = .default) {
        self.baseDirectory = baseDirectory
        self.fileManager = fileManager
    }

    /// 生产环境默认实例：落在 App 沙盒的 Application Support 目录，而不是 Documents——
    /// 对话历史是内部状态，不是用户想在"文件"App 里看到/导出/分享的文档。
    static func makeDefault() -> HistoryStore {
        let fm = FileManager.default
        let support = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        return HistoryStore(baseDirectory: support)
    }

    private var historyDirectory: URL {
        baseDirectory.appendingPathComponent("history", isDirectory: true)
    }

    private func fileURL(for characterID: String) -> URL {
        historyDirectory.appendingPathComponent("\(characterID).json")
    }

    /// 加载某角色的持久化历史。文件缺失、读取失败、JSON 解码失败——都返回空数组，从不抛出、从不崩溃。
    func load(for characterID: String) -> [PersistedTurn] {
        let url = fileURL(for: characterID)
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try JSONDecoder().decode([PersistedTurn].self, from: data)
        } catch {
            return []
        }
    }

    /// 保存某角色的历史（只保留最近 `maxPersistedTurns` 轮），原子写入：临时文件 + rename。
    /// 目录创建失败、编码失败、写入失败——都静默放弃，不影响调用方（内存里的历史依然有效）。
    func save(_ turns: [PersistedTurn], for characterID: String) {
        let trimmed = turns.count > Self.maxPersistedTurns
            ? Array(turns.suffix(Self.maxPersistedTurns))
            : turns

        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        do {
            try fileManager.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        } catch {
            return
        }

        let destination = fileURL(for: characterID)
        let tempURL = historyDirectory.appendingPathComponent(".\(characterID)-\(UUID().uuidString).tmp")
        do {
            try data.write(to: tempURL)
            // 先摘掉旧文件（如果存在），再把临时文件"重命名"到位——同一目录内的 move 是原子操作，
            // 不会出现"写到一半"的中间状态被别的读者看到。
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: tempURL, to: destination)
        } catch {
            try? fileManager.removeItem(at: tempURL)
        }
    }
}
