import Foundation

/// 首次引导的持久化状态：全程只出现一次（跨 App 安装也算一次），落笔即抢占。
/// 与 `ReplyHandStore`/`PaperStyleStore` 同一套持久化模式：`shared` 单例 + 可注入 `UserDefaults` 便于测试隔离。
/// 仅主线程访问 —— @MainActor 保证。
@MainActor
final class OnboardingStore: ObservableObject {
    static let shared = OnboardingStore()
    static let defaultsKey = "hasSeenOnboarding"

    /// 未设置过时 `UserDefaults.bool(forKey:)` 返回 false，天然代表"未见过"——无需额外的哨兵值。
    @Published private(set) var hasSeenOnboarding: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasSeenOnboarding = defaults.bool(forKey: Self.defaultsKey)
    }

    func markSeen() {
        guard !hasSeenOnboarding else { return }
        hasSeenOnboarding = true
        defaults.set(true, forKey: Self.defaultsKey)
    }
}

/// 引导墨迹的文案：按当前角色的语言选择——Ashford（`alwaysEnglish`）用英文，归野/沈砚用中文。
/// 纯函数，供 `DiaryView` 与测试共用。
enum OnboardingGuide {
    static func line(for hand: ReplyHand) -> String {
        hand.alwaysEnglish ? "Write something, then rest your pen…" : "写点什么，然后停笔片刻……"
    }
}
