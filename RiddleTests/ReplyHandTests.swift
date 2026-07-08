import XCTest
@testable import Riddle

final class ReplyHandTests: XCTestCase {
    func testAllHandFontsLoad() {
        for hand in ReplyHands.all {
            let font = UIFont(name: hand.fontName, size: 40)
            XCTAssertNotNil(font, "字体 \(hand.fontName)（\(hand.id)）应可加载")
        }
    }

    func testOrderIsShouzeWenkaiAshford() {
        XCTAssertEqual(ReplyHands.all.map(\.id), ["shouze", "wenkai", "ashford"])
    }

    func testAllHandsHaveNonEmptyPersona() {
        for hand in ReplyHands.all {
            XCTAssertFalse(hand.persona.isEmpty, "\(hand.id) 的 persona 不应为空")
        }
    }

    func testAlwaysEnglishOnlyAshford() {
        for hand in ReplyHands.all where hand.id != "ashford" {
            XCTAssertFalse(hand.alwaysEnglish, "\(hand.id) 不应强制英文")
        }
        XCTAssertTrue(ReplyHands.ashford.alwaysEnglish)
    }

    /// 手泽（三款之一）是唯一带 bankStyle 的手迹——其余两款字体骨架化手迹此字段恒为 nil；
    /// 且 HandBankStore 能加载手泽引用的真实字库、其 contains 对常用字返回 true（QuillLayer/
    /// HandPickerView 都经这条单例路径拿到同一份已加载的 bank）。
    @MainActor
    func testShouzeHasBankStyleAndHandBankStoreLoadsIt() throws {
        for hand in ReplyHands.all where hand.id != "shouze" {
            XCTAssertNil(hand.bankStyle, "字体款 \(hand.id) 不应带 bankStyle")
        }
        let bankStyle = try XCTUnwrap(ReplyHands.shouze.bankStyle)
        XCTAssertEqual(bankStyle, "neat-C002")

        let bank = try XCTUnwrap(HandBankStore.shared.bank(for: bankStyle))
        XCTAssertTrue(bank.contains("你"))
    }

    @MainActor
    func testDefaultIsShouze() {
        let suite = "ReplyHandTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ReplyHandStore(defaults: defaults)
        XCTAssertEqual(store.current.id, "shouze")
    }

    @MainActor
    func testRemovedHandIDFallsBackToShouze() {
        let suite = "ReplyHandTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("xiaxing", forKey: ReplyHandStore.defaultsKey)

        let store = ReplyHandStore(defaults: defaults)
        XCTAssertEqual(store.current.id, "shouze")
    }

    @MainActor
    func testPersistedWenkaiStaysWenkai() {
        let suite = "ReplyHandTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("wenkai", forKey: ReplyHandStore.defaultsKey)

        let store = ReplyHandStore(defaults: defaults)
        XCTAssertEqual(store.current.id, "wenkai")
    }

    @MainActor
    func testSelectPersists() {
        let suite = "ReplyHandTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ReplyHandStore(defaults: defaults)
        store.select("ashford")
        XCTAssertEqual(store.current.id, "ashford")

        let reloaded = ReplyHandStore(defaults: defaults)
        XCTAssertEqual(reloaded.current.id, "ashford")

        reloaded.select("not-a-real-hand")
        XCTAssertEqual(reloaded.current.id, "shouze")
    }
}
