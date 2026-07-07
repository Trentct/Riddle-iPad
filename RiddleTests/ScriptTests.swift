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

    func testWrapEnglish() {
        let lines = Script.wrap("Do you know anything about the Chamber of Secrets?",
                                font: dancing, maxWidth: 600)
        XCTAssertGreaterThanOrEqual(lines.count, 2)
        XCTAssertTrue(lines.allSatisfy { !$0.hasPrefix(" ") && !$0.hasSuffix(" ") })
        // 内容无丢失
        XCTAssertEqual(lines.joined(separator: " ").split(separator: " ").count, 9)
    }

    func testWrapCJK() {
        let lines = Script.wrap("哈利波特，一个多么有趣的名字，告诉我你的故事吧",
                                font: wenkai, maxWidth: 500)
        XCTAssertGreaterThanOrEqual(lines.count, 2)
        XCTAssertEqual(lines.joined(), "哈利波特，一个多么有趣的名字，告诉我你的故事吧")
    }

    func testWrapShortLineStaysOne() {
        XCTAssertEqual(Script.wrap("Hi", font: dancing, maxWidth: 600), ["Hi"])
    }

    struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return state
        }
    }

    func testHumanizeBoundedAndShapePreserving() {
        var rng = SeededRNG(seed: 42)
        // 50 点水平线，质心在 x=24.5。旋转 ±1.5° + 缩放 ±3% 对半长 25px 的最大位移
        // ≈ 25 * (sin(1.5°) + 0.03) ≈ 1.4，加上点级噪声振幅 0.4 → 上界给到 2.5 保守取整。
        let stroke: [[CGPoint]] = [(0..<50).map { CGPoint(x: CGFloat($0), y: 10) }]
        let out = Script.humanize(stroke, using: &rng)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].count, 50)
        for (a, b) in zip(stroke[0], out[0]) {
            XCTAssertLessThanOrEqual(abs(a.x - b.x), 2.5, "姿态变化越界")
            XCTAssertLessThanOrEqual(abs(a.y - b.y), 2.5, "姿态变化越界")
        }
        XCTAssertTrue(zip(stroke[0], out[0]).contains { $0 != $1 }, "应确有变化")
    }

    func testHumanizeKeepsTinyStrokesIntact() {
        var rng = SeededRNG(seed: 1)
        let tiny: [[CGPoint]] = [[CGPoint(x: 0, y: 0)]]
        XCTAssertEqual(Script.humanize(tiny, using: &rng)[0].count, 1)
    }
}
