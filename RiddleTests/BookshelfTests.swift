import XCTest
@testable import Riddle

/// 书架三本书对应 ReplyHands.all 三角色（顺序一致）、气质色表齐全、Logo 图能从 bundle 加载——
/// 三者任一断裂书架都会呈现残缺（缺书/缺色/缺图），所以分别断言。
final class BookshelfTests: XCTestCase {
    func testCoverColorTableHasAllThreeHandIDs() {
        for hand in ReplyHands.all {
            XCTAssertNotNil(BookCoverPalette.colors[hand.id], "\(hand.id) 应有气质色")
        }
        XCTAssertEqual(BookCoverPalette.colors.count, ReplyHands.all.count)
    }

    func testBooksMapToReplyHandsAllInOrder() {
        // 书架按 ReplyHands.all 顺序渲染三本书（归野→沈砚→Ashford），不是任意顺序。
        XCTAssertEqual(ReplyHands.all.map(\.id), ["shouze", "wenkai", "ashford"])
    }

    func testAllCoverLogosLoadFromBundle() throws {
        for hand in ReplyHands.all {
            let image = CoverImage.load(id: hand.id)
            XCTAssertNotNil(image, "Covers/\(hand.id).png 应能从 bundle 加载")
        }
    }

    func testCoverLogoNamedLookupMatchesKnownIDs() {
        // 直接用 UIImage(named:) 断言（brief 明确要求的加载方式），CoverImage.load 是它的兜底封装。
        XCTAssertNotNil(UIImage(named: "guiye"))
        XCTAssertNotNil(UIImage(named: "shenyan"))
        XCTAssertNotNil(UIImage(named: "ashford"))
    }
}
