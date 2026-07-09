import Foundation

/// 客户端侧的每日免费额度门控——在两种模式（直连 Moonshot / 走 riddle-backend）下都生效，
/// 是后端服务端限流（402）的纵深防御副本，也是没有后端时能独立演示付费页的关键。
/// 日历日按注入的 `calendar`/`now` 计算，天然可测（不依赖真实系统时钟）；`isPaidUnlocked`
/// 由 StoreManager 驱动，付费后无限次。
@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()

    /// FLAG: Trent 的产品决策——免费额度默认 5 次/天，随时可改这一个常量。
    static let freeRepliesPerDay = 100

    private static let countKey = "usageStore.count"
    private static let dayKey = "usageStore.day"

    @Published private(set) var todayCount: Int
    /// 是否已付费解锁——由 StoreManager 在初始化/购买/恢复后写入，不在这里发起任何 StoreKit 调用。
    @Published var isPaidUnlocked: Bool

    private let defaults: UserDefaults
    private let now: () -> Date
    private let calendar: Calendar

    init(defaults: UserDefaults = .standard,
         isPaidUnlocked: Bool = false,
         now: @escaping () -> Date = Date.init,
         calendar: Calendar = .current) {
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
        self.isPaidUnlocked = isPaidUnlocked

        let today = Self.dayString(for: now(), calendar: calendar)
        if defaults.string(forKey: Self.dayKey) == today {
            self.todayCount = defaults.integer(forKey: Self.countKey)
        } else {
            self.todayCount = 0
            defaults.set(today, forKey: Self.dayKey)
            defaults.set(0, forKey: Self.countKey)
        }
    }

    private static func dayString(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    /// 每次读/写前检查日历日是否已经翻篇（覆盖 App 常驻跨天、不重启的情况），翻篇则清零。
    private func rolloverIfNeeded() {
        let today = Self.dayString(for: now(), calendar: calendar)
        guard defaults.string(forKey: Self.dayKey) != today else { return }
        todayCount = 0
        defaults.set(today, forKey: Self.dayKey)
        defaults.set(0, forKey: Self.countKey)
    }

    /// 发起新一轮回信前调用：付费用户永远放行；免费用户当日计数达到上限则拒绝（触发付费页）。
    var canSendReply: Bool {
        rolloverIfNeeded()
        return isPaidUnlocked || todayCount < Self.freeRepliesPerDay
    }

    /// 一轮回信成功完成后调用；付费用户不计数。
    func recordReply() {
        rolloverIfNeeded()
        guard !isPaidUnlocked else { return }
        todayCount += 1
        defaults.set(todayCount, forKey: Self.countKey)
    }
}
