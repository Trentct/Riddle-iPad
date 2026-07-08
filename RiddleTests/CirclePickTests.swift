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

    func testFittedSizeClampsWidthAndKeepsAspect() {
        let fitted = HandPickerView.fittedSize(natural: CGSize(width: 2000, height: 100), maxWidth: 800, maxHeight: 64)
        XCTAssertEqual(fitted.width, 800, accuracy: 0.01)
        XCTAssertEqual(fitted.height, 40, accuracy: 0.01)   // aspect preserved
        let small = HandPickerView.fittedSize(natural: CGSize(width: 100, height: 50), maxWidth: 800, maxHeight: 64)
        XCTAssertEqual(small.width, 100, accuracy: 0.01)    // never upscale (scale capped at 1)
    }
}

final class SignaturePickTests: XCTestCase {
    /// 纸角落款的命中区域：100×50，位于原点方便算交叠比例。
    private let signatureFrame = CGRect(x: 0, y: 0, width: 100, height: 50)

    func testStrokeSolidlyAroundSignatureReturnsTrue() {
        // 包围盒完全覆盖落款区域：交叠比例 = 1.0。
        let strokeBounds = CGRect(x: -20, y: -20, width: 140, height: 90)
        XCTAssertTrue(SignaturePick.isCircled(strokeBounds: strokeBounds, signatureFrame: signatureFrame))
    }

    func testStrokeElsewhereReturnsFalse() {
        let strokeBounds = CGRect(x: 500, y: 500, width: 60, height: 60)
        XCTAssertFalse(SignaturePick.isCircled(strokeBounds: strokeBounds, signatureFrame: signatureFrame))
    }

    func testSmallOverlapReturnsFalse() {
        // 只蹭到落款右下角一小块：宽 20 高 20 = 面积 400，占落款面积 5000 的 8%，远低于阈值。
        let strokeBounds = CGRect(x: 80, y: 30, width: 40, height: 40)
        XCTAssertFalse(SignaturePick.isCircled(strokeBounds: strokeBounds, signatureFrame: signatureFrame))
    }

    func testThresholdBoundary() {
        // 交叠面积恰好等于阈值（60%）：应判为 true（>= 阈值）。
        let atThreshold = CGRect(x: -10, y: -10, width: 120, height: 40)   // overlap: 100×30 = 3000 / 5000 = 0.6
        XCTAssertTrue(SignaturePick.isCircled(strokeBounds: atThreshold, signatureFrame: signatureFrame))

        // 略低于阈值：应判为 false。
        let belowThreshold = CGRect(x: -10, y: -10, width: 120, height: 39)   // overlap: 100×29 = 2900 / 5000 = 0.58
        XCTAssertFalse(SignaturePick.isCircled(strokeBounds: belowThreshold, signatureFrame: signatureFrame))
    }
}
