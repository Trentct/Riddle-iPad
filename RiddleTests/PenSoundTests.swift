import XCTest
@testable import Riddle

/// 音频引擎本身不适合精确单测（真实发声效果需要人耳/真机核验，见 sound-report），
/// 这里只验证两件确定能自动化验证的事：不崩溃、以及开关门控生效。
final class PenSoundTests: XCTestCase {
    @MainActor
    func testStartStopDoesNotCrashWhenEnabled() {
        let suite = "PenSoundTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SoundStore(defaults: defaults)   // 默认开启
        let pen = PenSound(store: store)

        pen.start()
        XCTAssertTrue(pen.isActive)

        pen.stop()
        XCTAssertFalse(pen.isActive)

        // 多次 start/stop（模拟连续落笔的起止）不应崩溃或产生异常状态。
        pen.start()
        pen.start()
        pen.stop()
        pen.stop()
        XCTAssertFalse(pen.isActive)
    }

    @MainActor
    func testStartIsNoOpWhenDisabled() {
        let suite = "PenSoundTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SoundStore(defaults: defaults)
        store.setEnabled(false)
        let pen = PenSound(store: store)

        XCTAssertFalse(pen.shouldPlay())
        pen.start()
        XCTAssertFalse(pen.isActive)
    }

    @MainActor
    func testShouldPlayReflectsStoreState() {
        let suite = "PenSoundTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SoundStore(defaults: defaults)
        let pen = PenSound(store: store)
        XCTAssertTrue(pen.shouldPlay())

        store.setEnabled(false)
        XCTAssertFalse(pen.shouldPlay())

        store.setEnabled(true)
        XCTAssertTrue(pen.shouldPlay())
    }
}
