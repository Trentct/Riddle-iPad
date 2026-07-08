import XCTest
@testable import Riddle

/// HistoryStore 全部指向注入的临时目录（每个测试自己的 UUID 子目录），绝不碰真实的
/// Application Support 沙盒；测试结束后清理掉临时目录，避免在机器上留垃圾。
@MainActor
final class HistoryStoreTests: XCTestCase {
    private func makeTempStore() -> (HistoryStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
        return (HistoryStore(baseDirectory: dir), dir)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    func testSaveThenReloadRoundTripsAssistantReplyText() {
        let (store, dir) = makeTempStore()
        defer { cleanup(dir) }

        let turns = [
            PersistedTurn(role: "user", text: "(手写)"),
            PersistedTurn(role: "assistant", text: "墨迹浮现，我听见了你说的话。"),
        ]
        store.save(turns, for: "shouze")

        let loaded = store.load(for: "shouze")
        XCTAssertEqual(loaded, turns)
        XCTAssertEqual(loaded.last?.text, "墨迹浮现，我听见了你说的话。")
    }

    func testPerCharacterIsolation() {
        let (store, dir) = makeTempStore()
        defer { cleanup(dir) }

        let guiyeTurns = [PersistedTurn(role: "assistant", text: "归野の回信")]
        let shenyanTurns = [PersistedTurn(role: "assistant", text: "沈砚之回信")]

        store.save(guiyeTurns, for: "shouze")
        store.save(shenyanTurns, for: "wenkai")

        XCTAssertEqual(store.load(for: "shouze"), guiyeTurns)
        XCTAssertEqual(store.load(for: "wenkai"), shenyanTurns)

        // 再次保存其中一个角色，不应影响另一个角色的文件内容。
        store.save([PersistedTurn(role: "assistant", text: "归野の第二条回信")], for: "shouze")
        XCTAssertEqual(store.load(for: "wenkai"), shenyanTurns)
    }

    func testCorruptFileReturnsEmptyHistoryWithoutCrashing() {
        let (store, dir) = makeTempStore()
        defer { cleanup(dir) }

        let historyDir = dir.appendingPathComponent("history", isDirectory: true)
        try? FileManager.default.createDirectory(at: historyDir, withIntermediateDirectories: true)
        let corruptFile = historyDir.appendingPathComponent("ashford.json")
        try? "not valid json {{{".data(using: .utf8)!.write(to: corruptFile)

        let loaded = store.load(for: "ashford")
        XCTAssertEqual(loaded, [])
    }

    func testMissingFileReturnsEmptyHistory() {
        let (store, dir) = makeTempStore()
        defer { cleanup(dir) }

        XCTAssertEqual(store.load(for: "never-saved-character"), [])
    }

    func testSaveTrimsToMaxPersistedTurns() {
        let (store, dir) = makeTempStore()
        defer { cleanup(dir) }

        let many = (0..<30).map { PersistedTurn(role: "assistant", text: "第\($0)条") }
        store.save(many, for: "shouze")

        let loaded = store.load(for: "shouze")
        XCTAssertEqual(loaded.count, HistoryStore.maxPersistedTurns)
        XCTAssertEqual(loaded.last?.text, "第29条")
    }
}
