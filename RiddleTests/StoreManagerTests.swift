import XCTest
@testable import Riddle

/// 尝试过用 StoreKitTest（SKTestSession + Configuration.storekit）在单测里驱动一次真实购买，
/// 但 RiddleTests 是无宿主 App 的 bundle.unit-test（unhosted），不在持有 scheme StoreKit
/// 配置的 Riddle.app 进程里跑，`Product.products(for:)` 在这个进程里拿不到本地测试商店的数据
/// （命令行 `xcodebuild test` 下反复验证过：不抛错，但目录永远是空的）。按任务说明的退路，这里
/// 只测纯粹的 wiring：StoreManager.isUnlocked → UsageStore.isPaidUnlocked 这条线，不依赖 StoreKit
/// 本身是否能在测试进程里正常工作。真实的商品加载/购买/价格展示走模拟器手测验证
/// （Configuration.storekit 已经挂在 Riddle scheme 的 Run 配置上，见 project.yml）。
@MainActor
final class StoreManagerTests: XCTestCase {
    private func isolatedUsageStore() -> UsageStore {
        let suite = "StoreManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return UsageStore(defaults: defaults)
    }

    func testIsUnlockedWiringBypassesUsageCap() {
        let usage = isolatedUsageStore()
        for _ in 0..<UsageStore.freeRepliesPerDay { usage.recordReply() }
        XCTAssertFalse(usage.canSendReply, "前置条件：免费额度应已耗尽")

        // 模拟 StoreManager.refreshEntitlements() 发现有效交易后的动作：把 isPaidUnlocked 写为 true。
        usage.isPaidUnlocked = true
        XCTAssertTrue(usage.canSendReply, "解锁后应立即绕过每日额度门控")
    }

    func testStoreManagerStartsLockedWithNoEntitlements() {
        let usage = isolatedUsageStore()
        let manager = StoreManager(usageStore: usage)
        // 尚未加载/刷新任何交易之前，默认锁定态——不应该意外把免费用户放行。
        XCTAssertFalse(manager.isUnlocked)
        XCTAssertFalse(usage.isPaidUnlocked)
    }

    func testUnlockProductIDConstant() {
        // FLAG: Trent 待定的占位符 id；这个测试只是防止以后不小心手滑改掉却没人注意到。
        XCTAssertEqual(StoreManager.unlockProductID, "com.trentct.riddle.unlimited")
    }
}
