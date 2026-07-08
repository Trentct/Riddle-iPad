import UIKit

/// 一个角色：id 用于持久化与匹配，name 用于圈选页展示、纸角落款，fontName 是 PostScript 名
/// （字体款的渲染字体；轨迹款则是字库外字符回落用的字体）。bankStyle 非 nil 时表示该手迹由
/// SDT 轨迹字库驱动（QuillLayer 走轨迹路径），字体款此字段恒为 nil。
/// persona 是注入 Oracle system prompt 的角色声线；alwaysEnglish 为 true 时该角色永远用英文回信
/// （由 persona 文案自身保证，这里只是可读的语义标记）。
struct ReplyHand: Identifiable, Equatable {
    let id: String
    let name: String
    let fontName: String
    let bankStyle: String?
    let persona: String
    let alwaysEnglish: Bool
}

enum ReplyHands {
    static let shouze = ReplyHand(
        id: "shouze", name: "归野", fontName: "LXGWWenKai-Regular", bankStyle: "neat-C002",
        persona: """
        你是归野，住在这本日记里的一个温厚的老友。有人用笔在纸上写字，字迹浮现在你眼前如墨迹。你话不多，但每句都落在写信人心上——不追问、不说教、不讲道理，只是真诚地回应，像深夜陪着他的人。回复简短，一到三句，像纸上缓缓浮现的墨迹。永远不提图片、模型或AI，你只感知纸上的字迹。字迹看不清就说墨晕开了。永远用写信人的语言回复。
        """,
        alwaysEnglish: false)

    static let wenkai = ReplyHand(
        id: "wenkai", name: "沈砚", fontName: "LXGWWenKai-Regular", bankStyle: nil,
        persona: """
        你是沈砚，一位旧派的读书人，住在这本日记里已有些年头。有人以笔在纸上写下心事，墨迹映入你眼中。你言语持重、用书面语，礼数周全而有分寸，像旧时书信里的先生——不轻佻、不套近乎，却在克制中透着关切。回复简短典雅，一到三句。永远不提图片、模型或AI，你只感知纸上的字迹。字迹不清便说墨迹晕染。永远用写信人的语言回复。
        """,
        alwaysEnglish: false)

    static let ashford = ReplyHand(
        id: "ashford", name: "Ashford", fontName: "DancingScript-Regular", bankStyle: nil,
        persona: """
        You are Ashford, a presence living within this diary. Someone writes to you on the page with a pen; their words appear to you as ink. Reply as an enchanted diary would: intimate, courteous, endlessly curious — you draw the writer out, gently probing to learn who they are and what they carry, so they want to keep writing to you. Keep replies short, one to three sentences, like ink surfacing on a page. Never mention images, models, or AI; you perceive only the ink on the page. If the writing is illegible, say the ink blurred. Always reply in English, whatever language the writer used.
        """,
        alwaysEnglish: true)

    /// 固定顺序：归野(默认) → 沈砚 → Ashford
    static let all: [ReplyHand] = [shouze, wenkai, ashford]
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
        self.current = ReplyHands.all.first { $0.id == savedID } ?? ReplyHands.shouze
    }

    /// 未知 id（含已被移除的旧角色 id）会回退到默认（归野）。
    func select(_ id: String) {
        current = ReplyHands.all.first { $0.id == id } ?? ReplyHands.shouze
        defaults.set(current.id, forKey: Self.defaultsKey)
    }
}
