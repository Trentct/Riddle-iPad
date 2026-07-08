import UIKit

/// 一款回信笔迹：id 用于持久化与匹配，name 用于圈选页展示，fontName 是 PostScript 名（字体款的渲染字体；
/// 轨迹款则是字库外字符回落用的字体）。bankStyle 非 nil 时表示该手迹由 SDT 轨迹字库驱动（QuillLayer 走轨迹路径），
/// 字体款（现有五款）此字段恒为 nil。
struct ReplyHand: Identifiable, Equatable {
    let id: String
    let name: String
    let fontName: String
    let bankStyle: String?
}

enum ReplyHands {
    static let wenkai = ReplyHand(id: "wenkai", name: "端楷", fontName: "LXGWWenKai-Regular", bankStyle: nil)
    static let xiaxing = ReplyHand(id: "xiaxing", name: "行云", fontName: "Slidexiaxing-Regular", bankStyle: nil)
    static let hanchan = ReplyHand(id: "hanchan", name: "寒蝉", fontName: "YFHCT", bankStyle: nil)
    static let longcang = ReplyHand(id: "longcang", name: "松风", fontName: "LongCang-Regular", bankStyle: nil)
    static let maocao = ReplyHand(id: "maocao", name: "醉墨", fontName: "LiuJianMaoCao-Regular", bankStyle: nil)
    static let shouze = ReplyHand(id: "shouze", name: "手泽", fontName: "LXGWWenKai-Regular", bankStyle: "neat-C002")

    /// 固定顺序：端楷 → 行云 → 寒蝉 → 松风 → 醉墨 → 手泽（手泽为 SDT 轨迹字库驱动，其余为字体骨架化）
    static let all: [ReplyHand] = [wenkai, xiaxing, hanchan, longcang, maocao, shouze]
}

/// 当前回信笔迹的持久化存储与切换逻辑。`shared` 是全局单例，QuillLayer 与圈选页共用同一份状态。
/// 仅主线程访问 —— @MainActor 保证。
@MainActor
final class ReplyHandStore: ObservableObject {
    static let shared = ReplyHandStore()
    static let defaultsKey = "replyHandID"

    @Published private(set) var current: ReplyHand

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedID = defaults.string(forKey: Self.defaultsKey)
        self.current = ReplyHands.all.first { $0.id == savedID } ?? ReplyHands.xiaxing
    }

    /// 未知 id 会回退到默认（夏行楷）。
    func select(_ id: String) {
        current = ReplyHands.all.first { $0.id == id } ?? ReplyHands.xiaxing
        defaults.set(current.id, forKey: Self.defaultsKey)
    }
}
