import XCTest
@testable import Riddle

final class CirclePickTests: XCTestCase {
    /// 四行样字的行框：行高 60，行间距 20，宽度 300。
    private let rowFrames: [CGRect] = [
        CGRect(x: 0, y: 0, width: 300, height: 60),     // 第 1 行
        CGRect(x: 0, y: 80, width: 300, height: 60),    // 第 2 行
        CGRect(x: 0, y: 160, width: 300, height: 60),   // 第 3 行
        CGRect(x: 0, y: 240, width: 300, height: 60),   // 第 4 行
    ]

    func testCircleMostlyOverSecondRowPicksIt() {
        // 圈选包围盒主体落在第 2 行 (index 1) 上，略微越界到第 1/3 行。
        let strokeBounds = CGRect(x: 20, y: 70, width: 200, height: 80)
        XCTAssertEqual(CirclePick.pickRow(strokeBounds: strokeBounds, rowFrames: rowFrames), 1)
    }

    func testStrokeIntersectingNothingReturnsNil() {
        let strokeBounds = CGRect(x: 0, y: 1000, width: 100, height: 20)
        XCTAssertNil(CirclePick.pickRow(strokeBounds: strokeBounds, rowFrames: rowFrames))
    }

    func testStrokeSpanningTwoRowsPicksLargerOverlap() {
        // 跨第 1/2 行 (index 0/1)，与第 1 行交叠面积更大。
        let strokeBounds = CGRect(x: 0, y: 30, width: 300, height: 60)
        XCTAssertEqual(CirclePick.pickRow(strokeBounds: strokeBounds, rowFrames: rowFrames), 0)
    }
}
