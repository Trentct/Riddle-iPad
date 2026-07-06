import XCTest
@testable import Riddle

final class PaperStyleTests: XCTestCase {
    func testCycleWrapsAroundBothDirections() {
        let suite = "PaperStyleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PaperStyleStore(defaults: defaults)

        XCTAssertEqual(store.current.id, "plain")

        store.cycle(1) // parchment
        store.cycle(1) // ruled
        store.cycle(1) // rice
        store.cycle(1) // 应环绕回 plain
        XCTAssertEqual(store.current.id, "plain")

        store.cycle(-1) // 反向环绕应回到最后一个 rice
        XCTAssertEqual(store.current.id, "rice")
    }

    func testPersistenceRoundTrip() {
        let suite = "PaperStyleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PaperStyleStore(defaults: defaults)
        store.cycle(1)
        store.cycle(1) // 现在是 "ruled"
        XCTAssertEqual(store.current.id, "ruled")

        // 用同一个 UserDefaults suite 新建一个 store，应恢复到上次的选择
        let reloaded = PaperStyleStore(defaults: defaults)
        XCTAssertEqual(reloaded.current.id, "ruled")
    }
}
