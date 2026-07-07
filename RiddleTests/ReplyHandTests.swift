import XCTest
@testable import Riddle

final class ReplyHandTests: XCTestCase {
    func testAllFourHandFontsLoad() {
        for hand in ReplyHands.all {
            let font = UIFont(name: hand.fontName, size: 40)
            XCTAssertNotNil(font, "字体 \(hand.fontName)（\(hand.id)）应可加载")
        }
    }

    @MainActor
    func testDefaultIsXiaxing() {
        let suite = "ReplyHandTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ReplyHandStore(defaults: defaults)
        XCTAssertEqual(store.current.id, "xiaxing")
    }

    @MainActor
    func testSelectPersists() {
        let suite = "ReplyHandTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ReplyHandStore(defaults: defaults)
        store.select("longcang")
        XCTAssertEqual(store.current.id, "longcang")

        let reloaded = ReplyHandStore(defaults: defaults)
        XCTAssertEqual(reloaded.current.id, "longcang")

        reloaded.select("not-a-real-hand")
        XCTAssertEqual(reloaded.current.id, "xiaxing")
    }
}
