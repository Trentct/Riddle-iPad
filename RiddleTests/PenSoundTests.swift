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

        let store = SoundStore(defaults: defaults)
        store.setEnabled(true)   // 音效默认已下线，此测试显式开启以验证引擎门控
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
        store.setEnabled(true)   // 音效默认已下线，显式开启验证 shouldPlay 跟随开关
        XCTAssertTrue(pen.shouldPlay())

        store.setEnabled(false)
        XCTAssertFalse(pen.shouldPlay())

        store.setEnabled(true)
        XCTAssertTrue(pen.shouldPlay())
    }

    // MARK: - 笔速 → 强度 的纯函数（唯一能脱离 AVAudioEngine 精确断言的合成逻辑）

    @MainActor
    func testNormalizedIntensityIsZeroForNonPositiveOrInvalidSpeed() {
        XCTAssertEqual(PenSound.normalizedIntensity(forSpeed: 0), 0)
        XCTAssertEqual(PenSound.normalizedIntensity(forSpeed: -50), 0)
        XCTAssertEqual(PenSound.normalizedIntensity(forSpeed: .nan), 0)
        XCTAssertEqual(PenSound.normalizedIntensity(forSpeed: .infinity), 0)
    }

    @MainActor
    func testNormalizedIntensityIsMonotonicallyNonDecreasing() {
        let samples: [CGFloat] = [10, 50, 150, 300, 600, 900, 1200, 1400, 2000, 5000]
        let values = samples.map { PenSound.normalizedIntensity(forSpeed: $0) }
        for (a, b) in zip(values, values.dropFirst()) {
            XCTAssertLessThanOrEqual(a, b, "强度应随笔速单调不减")
        }
    }

    @MainActor
    func testNormalizedIntensityClampsAtAndBeyondMaxSpeed() {
        let atCap = PenSound.normalizedIntensity(forSpeed: 1400)
        let wellBeyondCap = PenSound.normalizedIntensity(forSpeed: 10_000)
        XCTAssertEqual(atCap, 1, accuracy: 0.0001)
        XCTAssertEqual(wellBeyondCap, 1, accuracy: 0.0001)
    }

    @MainActor
    func testNormalizedIntensityStaysWithinUnitRange() {
        for speed: CGFloat in stride(from: 0, through: 3000, by: 37) {
            let value = PenSound.normalizedIntensity(forSpeed: speed)
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThanOrEqual(value, 1)
        }
    }

    @MainActor
    func testUpdateVelocityIsNoOpWhenNotActive() {
        // 引擎没在播放（未 start()）时喂笔速，不应产生崩溃或异常状态——纯粹的安全性回归。
        let suite = "PenSoundTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SoundStore(defaults: defaults)
        store.setEnabled(true)   // 音效默认已下线，显式开启以测引擎门控
        let pen = PenSound(store: store)

        pen.updateVelocity(500)
        XCTAssertFalse(pen.isActive)

        pen.start()
        pen.updateVelocity(500)
        XCTAssertTrue(pen.isActive)
        pen.stop()
    }
}
