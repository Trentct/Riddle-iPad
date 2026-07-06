import XCTest
@testable import Riddle

final class OracleTests: XCTestCase {
    func testSentenceSplitterCN() {
        var s = SentenceSplitter()
        var out = s.push("哈利·波特——真是个")
        XCTAssertTrue(out.isEmpty)
        out = s.push("有趣的名字。告诉我，哈利")
        XCTAssertEqual(out, ["哈利·波特——真是个有趣的名字。"])
        out = s.push("，是什么把你带到这本日记？")
        XCTAssertEqual(out, ["告诉我，哈利，是什么把你带到这本日记？"])
        XCTAssertNil(s.flush())
    }

    func testSentenceSplitterEN() {
        var s = SentenceSplitter()
        let out = s.push("An interesting name indeed. Tell me more")
        XCTAssertEqual(out, ["An interesting name indeed."])
        XCTAssertEqual(s.flush(), "Tell me more")
    }

    func testSSEParseLine() {
        let line = #"data: {"choices":[{"delta":{"content":"你好"}}]}"#
        XCTAssertEqual(SSE.parseLine(line), "你好")
        XCTAssertNil(SSE.parseLine("data: [DONE]"))
        XCTAssertNil(SSE.parseLine(": keep-alive"))
        XCTAssertNil(SSE.parseLine(#"data: {"choices":[{"delta":{}}]}"#))
    }

    @MainActor
    func testOracleSmoke() async throws {
        try XCTSkipIf(Secrets.apiKey.isEmpty || Secrets.apiKey.contains("换成"), "未配置 key")
        let img = UIGraphicsImageRenderer(size: .init(width: 400, height: 200)).pngData { ctx in
            UIColor.white.setFill(); ctx.fill(.init(x: 0, y: 0, width: 400, height: 200))
            ("你好，我叫哈利·波特" as NSString).draw(at: .init(x: 20, y: 80),
                withAttributes: [.font: UIFont.systemFont(ofSize: 32), .foregroundColor: UIColor.black])
        }
        var sentences: [String] = []
        for try await s in Oracle().ask(pagePNG: img) { sentences.append(s) }
        XCTAssertFalse(sentences.isEmpty)
        print("Oracle 回信: \(sentences)")
    }
}
