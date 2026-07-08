import XCTest
@testable import Riddle

final class SoundStoreTests: XCTestCase {
    @MainActor
    func testDefaultsToEnabled() {
        let suite = "SoundStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SoundStore(defaults: defaults)
        XCTAssertTrue(store.isEnabled)
    }

    @MainActor
    func testSetEnabledFalsePersists() {
        let suite = "SoundStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SoundStore(defaults: defaults)
        store.setEnabled(false)
        XCTAssertFalse(store.isEnabled)

        // 同一 suite 新建的 store 应恢复到「已关闭」，而不是回退到默认开启。
        let reloaded = SoundStore(defaults: defaults)
        XCTAssertFalse(reloaded.isEnabled)
    }

    @MainActor
    func testToggleFlipsState() {
        let suite = "SoundStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SoundStore(defaults: defaults)
        XCTAssertTrue(store.isEnabled)
        store.toggle()
        XCTAssertFalse(store.isEnabled)
        store.toggle()
        XCTAssertTrue(store.isEnabled)
    }
}
