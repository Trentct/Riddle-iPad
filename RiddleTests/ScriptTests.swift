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
}
