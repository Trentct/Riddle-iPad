import UIKit

/// 一款纸的完整视觉定义：纸色、墨色、纹理与是否画线。
struct PaperStyle: Identifiable, Equatable {
    let id: String
    let name: String
    let paperColor: UIColor
    let userInk: UIColor
    let quillInk: UIColor
    let noiseOpacity: CGFloat
    let vignetteOpacity: CGFloat
    let ruled: Bool
    let riceFiber: Bool

    static func == (lhs: PaperStyle, rhs: PaperStyle) -> Bool { lhs.id == rhs.id }
}

enum PaperStyles {
    static let plain = PaperStyle(
        id: "plain", name: "素笺",
        paperColor: UIColor(red: 0xF2 / 255, green: 0xED / 255, blue: 0xE1 / 255, alpha: 1),
        userInk: UIColor(red: 0x1A / 255, green: 0x1A / 255, blue: 0x2E / 255, alpha: 1),
        quillInk: UIColor(red: 0x0F / 255, green: 0x0F / 255, blue: 0x23 / 255, alpha: 1),
        noiseOpacity: 0.05, vignetteOpacity: 0.08, ruled: false, riceFiber: false)

    static let parchment = PaperStyle(
        id: "parchment", name: "羊皮纸",
        paperColor: UIColor(red: 0xEA / 255, green: 0xD9 / 255, blue: 0xB0 / 255, alpha: 1),
        userInk: UIColor(red: 0x40 / 255, green: 0x2D / 255, blue: 0x16 / 255, alpha: 1),
        quillInk: UIColor(red: 0x2E / 255, green: 0x1F / 255, blue: 0x0E / 255, alpha: 1),
        noiseOpacity: 0.09, vignetteOpacity: 0.16, ruled: false, riceFiber: false)

    static let ruled = PaperStyle(
        id: "ruled", name: "横线信纸",
        paperColor: UIColor(red: 0xF7 / 255, green: 0xF4 / 255, blue: 0xEC / 255, alpha: 1),
        userInk: UIColor(red: 0x1F / 255, green: 0x3A / 255, blue: 0x6E / 255, alpha: 1),
        quillInk: UIColor(red: 0x12 / 255, green: 0x26 / 255, blue: 0x4A / 255, alpha: 1),
        noiseOpacity: 0.04, vignetteOpacity: 0.08, ruled: true, riceFiber: false)

    static let rice = PaperStyle(
        id: "rice", name: "宣纸",
        paperColor: UIColor(red: 0xF6 / 255, green: 0xF3 / 255, blue: 0xEA / 255, alpha: 1),
        userInk: UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1C / 255, alpha: 1),
        quillInk: UIColor(red: 0x10 / 255, green: 0x10 / 255, blue: 0x10 / 255, alpha: 1),
        noiseOpacity: 0.06, vignetteOpacity: 0.08, ruled: false, riceFiber: true)

    /// 固定顺序：素笺 → 羊皮纸 → 横线信纸 → 宣纸
    static let all: [PaperStyle] = [plain, parchment, ruled, rice]
}

/// 横线信纸的画线参数：与 QuillLayer 的行高(44pt)/起始位置(pageHeight/3) 对齐。
enum RuledMetrics {
    static let lineSpacing: CGFloat = 44
    static let lineColor = UIColor(red: 0xB9 / 255, green: 0xC4 / 255, blue: 0xD6 / 255, alpha: 1)
    static let lineWidth: CGFloat = 0.5
    static let marginX: CGFloat = 64
    static let marginColor = UIColor(red: 0xD9 / 255, green: 0x8B / 255, blue: 0x8B / 255, alpha: 1)
    static let marginWidth: CGFloat = 1
}

/// 当前纸张样式的持久化存储与切换逻辑。`shared` 是全局单例，Ink 与所有 UI 共用同一份状态。
/// 仅主线程访问（所有调用点：手势回调、@MainActor TurnEngine、主线程动画）——如未来引入后台访问需改为 @MainActor。
final class PaperStyleStore: ObservableObject {
    static let shared = PaperStyleStore()
    static let defaultsKey = "paperStyleID"

    @Published private(set) var current: PaperStyle

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedID = defaults.string(forKey: Self.defaultsKey)
        self.current = PaperStyles.all.first { $0.id == savedID } ?? PaperStyles.plain
    }

    /// direction: +1 切到下一款（环绕），-1 切到上一款（环绕）
    func cycle(_ direction: Int) {
        let all = PaperStyles.all
        let idx = all.firstIndex(where: { $0.id == current.id }) ?? 0
        let count = all.count
        let next = ((idx + direction) % count + count) % count
        current = all[next]
        defaults.set(current.id, forKey: Self.defaultsKey)
    }
}
