import XCTest
@testable import Riddle

final class OnboardingStoreTests: XCTestCase {
    @MainActor
    func testDefaultsToUnseen() {
        let suite = "OnboardingStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = OnboardingStore(defaults: defaults)
        XCTAssertFalse(store.hasSeenOnboarding)
    }

    @MainActor
    func testMarkSeenFlipsAndPersists() {
        let suite = "OnboardingStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = OnboardingStore(defaults: defaults)
        store.markSeen()
        XCTAssertTrue(store.hasSeenOnboarding)

        // 同一 suite 新建的 store 应恢复到"已见过"，不会再次触发引导。
        let reloaded = OnboardingStore(defaults: defaults)
        XCTAssertTrue(reloaded.hasSeenOnboarding)
    }

    @MainActor
    func testMarkSeenIsIdempotent() {
        let suite = "OnboardingStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = OnboardingStore(defaults: defaults)
        store.markSeen()
        store.markSeen()
        XCTAssertTrue(store.hasSeenOnboarding)
    }

    func testGuideLineIsEnglishForAshford() {
        XCTAssertEqual(OnboardingGuide.line(for: ReplyHands.ashford), "Write something, then rest your pen…")
    }

    func testGuideLineIsChineseForShouzeAndWenkai() {
        XCTAssertEqual(OnboardingGuide.line(for: ReplyHands.shouze), "写点什么，然后停笔片刻……")
        XCTAssertEqual(OnboardingGuide.line(for: ReplyHands.wenkai), "写点什么，然后停笔片刻……")
    }
}
