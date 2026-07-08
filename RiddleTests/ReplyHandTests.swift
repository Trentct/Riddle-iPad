import XCTest
@testable import Riddle

final class ReplyHandTests: XCTestCase {
    func testAllHandFontsLoad() {
        for hand in ReplyHands.all {
            let font = UIFont(name: hand.fontName, size: 40)
            XCTAssertNotNil(font, "字体 \(hand.fontName)（\(hand.id)）应可加载")
        }
    }

    func testOrderIsWenkaiXiaxingHanchanLongcangMaocaoShouze() {
        XCTAssertEqual(ReplyHands.all.map(\.id), ["wenkai", "xiaxing", "hanchan", "longcang", "maocao", "shouze"])
    }

    /// 手泽（第六款）是唯一带 bankStyle 的手迹——其余五款字体骨架化手迹此字段恒为 nil；
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
