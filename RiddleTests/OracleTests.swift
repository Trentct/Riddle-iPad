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
    func testOracleSystemPromptUsesSelectedCharacterPersona() {
        let suite = "OracleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ReplyHandStore(defaults: defaults)

        // Oracle 读取全局单例 ReplyHandStore.shared，这里直接对齐 shared 的当前选择来做断言，
        // 覆盖：默认角色（归野，非 alwaysEnglish，prompt 就是 persona 本身）与切换后（Ashford，
        // alwaysEnglish，prompt 是 persona + 额外强提示行）两种场景。
        ReplyHandStore.shared.select(store.current.id) // 归野
        XCTAssertEqual(Oracle().systemPrompt(), ReplyHands.shouze.persona)

        ReplyHandStore.shared.select("ashford")
        XCTAssertTrue(Oracle().systemPrompt().hasPrefix(ReplyHands.ashford.persona))
        XCTAssertTrue(Oracle().systemPrompt().contains("Always reply in English"))

        // 复位，避免影响其它测试对 shared 单例默认状态的假设
        ReplyHandStore.shared.select("shouze")
    }

    /// alwaysEnglish 角色的额外强提示行——不是靠 persona 文案本身，而是 Oracle 按 bool 主动追加的。
    @MainActor
    func testAshfordSystemPromptHasExtraEnglishGuardShouzeDoesNot() {
        ReplyHandStore.shared.select("ashford")
        XCTAssertTrue(Oracle().systemPrompt().contains("Reply ONLY in English."))

        ReplyHandStore.shared.select("shouze")
        XCTAssertFalse(Oracle().systemPrompt().contains("Reply ONLY in English."))
    }

    // MARK: - buildRequest：直连 Moonshot 路径必须与冒烟测试之前的行为字节级一致；
    // 后端路径按 riddle-backend/docs/APP_INTEGRATION.md 的契约断言请求形状，不需要真的连后端。

    @MainActor
    func testBuildRequestDirectMoonshotPathUnchanged() throws {
        let messages: [[String: Any]] = [["role": "user", "content": "hi"]]
        let req = try Oracle.buildRequest(messages: messages, systemPrompt: "你是归野", useBackend: false)

        XCTAssertEqual(req.url?.absoluteString, Secrets.baseURL + "/chat/completions")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer \(Secrets.apiKey)")
        XCTAssertNil(req.value(forHTTPHeaderField: "X-Device-Id"))

        let body = try XCTUnwrap(req.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, Secrets.model)
        XCTAssertEqual(json["stream"] as? Bool, true)
        let sentMessages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(sentMessages.first?["role"] as? String, "system")
    }

    @MainActor
    func testBuildRequestBackendPathShapedPerContract() throws {
        let messages: [[String: Any]] = [["role": "user", "content": "hi"]]
        let req = try Oracle.buildRequest(messages: messages, systemPrompt: "你是归野", useBackend: true)

        XCTAssertEqual(req.url?.absoluteString, Secrets.backendURL + "/v1/reply")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer \(Secrets.appSharedSecret)")
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-Device-Id"), DeviceId.current)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(req.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        // system 是独立顶层字段，不再拼进 messages 数组；model 不再由 App 发送。
        XCTAssertEqual(json["system"] as? String, "你是归野")
        XCTAssertNil(json["model"])
        let sentMessages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(sentMessages.count, messages.count)
        XCTAssertEqual(sentMessages.first?["role"] as? String, "user")
    }

    func testDeviceIdIsStableAcrossCalls() {
        XCTAssertEqual(DeviceId.current, DeviceId.current)
    }

    func test402MapsToQuotaExceeded() {
        XCTAssertEqual(OracleError.forStatusCode(402) as? OracleError, .quotaExceeded)
    }

    func test200MapsToNoError() {
        XCTAssertNil(OracleError.forStatusCode(200))
    }

    func testOtherNon200MapsToGenericError() {
        let error = OracleError.forStatusCode(500)
        XCTAssertNotNil(error)
        XCTAssertNil(error as? OracleError)
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
