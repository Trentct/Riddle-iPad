import XCTest
@testable import Riddle

final class ScriptTests: XCTestCase {
    var dancing: UIFont { UIFont(name: "DancingScript-Regular", size: 96)! }
    var wenkai: UIFont { UIFont(name: "LXGWWenKai-Regular", size: 96)! }

    func testRasterizeProducesInk() {
        let mask = Script.rasterize("Yes, Harry?", font: dancing)
        XCTAssertGreaterThan(mask.width, 100)
        XCTAssertGreaterThan(mask.height, 50)
        let inked = mask.pixels.filter { $0 }.count
        XCTAssertGreaterThan(inked, 500, "应有大量墨点")
    }

    func testRasterizeCJK() {
        let mask = Script.rasterize("你好哈利", font: wenkai)
        XCTAssertGreaterThan(mask.pixels.filter { $0 }.count, 500)
    }

    func testRasterizeEmpty() {
        let mask = Script.rasterize("", font: dancing)
        XCTAssertEqual(mask.pixels.filter { $0 }.count, 0)
    }

    func testThinSlimsGlyphs() {
        var mask = Script.rasterize("Yes, Harry?", font: dancing)
        let before = mask.pixels.filter { $0 }.count
        Script.thin(&mask)
        let after = mask.pixels.filter { $0 }.count
        XCTAssertGreaterThan(after, 0)
        XCTAssertLessThan(after * 3, before, "细化应显著削瘦字形: \(before) -> \(after)")
    }

    func testThinCJK() {
        var mask = Script.rasterize("哈", font: wenkai)
        let before = mask.pixels.filter { $0 }.count
        Script.thin(&mask)
        let after = mask.pixels.filter { $0 }.count
        XCTAssertGreaterThan(after, 0)
        XCTAssertLessThan(after, before)
    }

    func testTraceFullPipeline() {
        var mask = Script.rasterize("Yes, Harry?", font: dancing)
        Script.thin(&mask)
        let strokes = Script.trace(mask)
        XCTAssertFalse(strokes.isEmpty)
        let total = strokes.map(\.count).reduce(0, +)
        XCTAssertGreaterThan(total, 200, "路径总点数应可观，实际 \(total)")
        // 从左到右排序
        let minXs = strokes.map { s in s.map(\.x).min()! }
        XCTAssertEqual(minXs, minXs.sorted())
        // 每条笔画至少 3 点
        XCTAssertTrue(strokes.allSatisfy { $0.count >= 3 })
    }

    func testTraceCJKPipeline() {
        var mask = Script.rasterize("你好", font: wenkai)
        Script.thin(&mask)
        let strokes = Script.trace(mask)
        XCTAssertFalse(strokes.isEmpty)
    }
}
