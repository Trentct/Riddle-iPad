import XCTest
@testable import Riddle

@MainActor
final class UsageStoreTests: XCTestCase {
    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "UsageStoreTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    private func cleanup(_ defaults: UserDefaults, _ suite: String) {
        defaults.removePersistentDomain(forName: suite)
    }

    func testStartsAtZeroAndUnderLimitCanSend() {
        let (defaults, suite) = isolatedDefaults()
        defer { cleanup(defaults, suite) }

        let store = UsageStore(defaults: defaults)
        XCTAssertEqual(store.todayCount, 0)
        XCTAssertTrue(store.canSendReply)
    }

    func testRecordReplyIncrementsAndPersists() {
        let (defaults, suite) = isolatedDefaults()
        defer { cleanup(defaults, suite) }

        let store = UsageStore(defaults: defaults)
        store.recordReply()
        store.recordReply()
        XCTAssertEqual(store.todayCount, 2)

        let reloaded = UsageStore(defaults: defaults)
        XCTAssertEqual(reloaded.todayCount, 2)
    }

    func testCapEnforcedAtFreeLimit() {
        let (defaults, suite) = isolatedDefaults()
        defer { cleanup(defaults, suite) }

        let store = UsageStore(defaults: defaults)
        for _ in 0..<UsageStore.freeRepliesPerDay {
            XCTAssertTrue(store.canSendReply)
            store.recordReply()
        }
        XCTAssertFalse(store.canSendReply)
        XCTAssertEqual(store.todayCount, UsageStore.freeRepliesPerDay)
    }

    func testPaidBypassesCapAndDoesNotIncrementCount() {
        let (defaults, suite) = isolatedDefaults()
        defer { cleanup(defaults, suite) }

        let store = UsageStore(defaults: defaults, isPaidUnlocked: true)
        for _ in 0..<(UsageStore.freeRepliesPerDay + 3) {
            XCTAssertTrue(store.canSendReply)
            store.recordReply()
        }
        // 付费用户不计数——recordReply 是 no-op。
        XCTAssertEqual(store.todayCount, 0)
    }

    func testTogglingPaidMidSessionImmediatelyBypassesCap() {
        let (defaults, suite) = isolatedDefaults()
        defer { cleanup(defaults, suite) }

        let store = UsageStore(defaults: defaults)
        for _ in 0..<UsageStore.freeRepliesPerDay { store.recordReply() }
        XCTAssertFalse(store.canSendReply)

        store.isPaidUnlocked = true
        XCTAssertTrue(store.canSendReply)
    }

    func testCalendarDayResetClearsCount() {
        let (defaults, suite) = isolatedDefaults()
        defer { cleanup(defaults, suite) }

        var current = Date(timeIntervalSince1970: 1_700_000_000) // 固定起点，注入时钟
        let store = UsageStore(defaults: defaults, now: { current }, calendar: .current)
        for _ in 0..<UsageStore.freeRepliesPerDay { store.recordReply() }
        XCTAssertFalse(store.canSendReply)

        // 快进 25 小时——跨了一个日历日
        current = current.addingTimeInterval(25 * 3600)
        XCTAssertTrue(store.canSendReply)
        XCTAssertEqual(store.todayCount, 0)
    }

    func testSameDayAcrossReloadsDoesNotReset() {
        let (defaults, suite) = isolatedDefaults()
        defer { cleanup(defaults, suite) }

        let fixed = Date(timeIntervalSince1970: 1_700_000_000)
        let store = UsageStore(defaults: defaults, now: { fixed })
        store.recordReply()
        store.recordReply()

        // 同一天重新构造（比如冷启动），计数应保留。
        let reloaded = UsageStore(defaults: defaults, now: { fixed.addingTimeInterval(60) })
        XCTAssertEqual(reloaded.todayCount, 2)
    }
}
