import AVFoundation

/// 笔尖书写音效：合成噪声经带通滤波，模拟纸上运笔的沙沙声。零素材、纯代码合成——
/// 不需要采买/授权任何音频文件，也没有额外的 App 体积开销。
///
/// 音频会话用 `.ambient`：遵守静音键（用户静音时天然不发声）、与其他 App 的音频混音
/// （不会打断用户正在放的音乐），这是日记类 App 的底线要求。
///
/// 门控：每次 `start()` 都先查 `SoundStore.isEnabled`，关闭时整个引擎都不会被触碰
/// （见 `shouldPlay()`，一个不依赖引擎状态的纯判断，方便单测）。
@MainActor
final class PenSound {
    static let shared = PenSound()

    private let store: SoundStore
    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()

    /// 引擎当前是否处于「正在发声/淡入中」的逻辑活跃态——不等价于 `engine.isRunning`
    /// （停止时先淡出、淡出完成才真正 pause 引擎），供 `stop()` 内部判断与测试断言使用。
    private(set) var isActive = false

    private var fadeTask: Task<Void, Never>?

    private let targetVolume: Float = 0.05   // 刻意压低：锦上添花的底噪，不能抢戏
    private let fadeInSeconds: Double = 0.06
    private let fadeOutSeconds: Double = 0.22
    private let fadeStep: Double = 0.02

    init(store: SoundStore = .shared) {
        self.store = store
        buildGraph()
    }

    /// 纯门控判断，不触碰引擎——供 `start()` 复用，也单独暴露给测试。
    func shouldPlay() -> Bool { store.isEnabled }

    /// 开始书写：用户落笔或 QuillLayer 开始写一句时调用。若开关已关闭，整个函数是 no-op，
    /// 引擎既不会被 configure、也不会被 start——不产生任何副作用。
    func start() {
        guard shouldPlay() else { return }
        fadeTask?.cancel()

        if !engine.isRunning {
            do {
                try configureAudioSession()
                try engine.start()
            } catch {
                // 音效是锦上添花，绝不能因为音频会话/引擎起不来而影响书写体验，静默放弃即可。
                return
            }
        }
        isActive = true
        rampVolume(to: targetVolume, seconds: fadeInSeconds)
    }

    /// 停止书写：笔尖离开纸面/QuillLayer 一句写完时调用。淡出后暂停引擎（不是彻底 stop），
    /// 下次 `start()` 可以立即续上，没有引擎冷启动的延迟。
    func stop() {
        fadeTask?.cancel()
        isActive = false
        rampVolume(to: 0, seconds: fadeOutSeconds) { [weak self] in
            guard let self, !self.isActive else { return }   // 淡出途中又被 start() 抢占，别误停
            if self.engine.isRunning { self.engine.pause() }
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        // .ambient：被静音键和锁屏静音，且默认与其他 App 音频混音——日记类 App 绝不能打断用户正播的音乐。
        try session.setCategory(.ambient, options: [.mixWithOthers])
        try session.setActive(true, options: [])
    }

    private func rampVolume(to target: Float, seconds: Double, completion: (() -> Void)? = nil) {
        let mixer = self.mixer
        let steps = max(Int(seconds / fadeStep), 1)
        let start = mixer.outputVolume
        let stepNanos = UInt64(fadeStep * 1_000_000_000)
        fadeTask = Task { @MainActor in
            for i in 1...steps {
                try? await Task.sleep(nanoseconds: stepNanos)
                guard !Task.isCancelled else { return }
                let t = Float(i) / Float(steps)
                mixer.outputVolume = start + (target - start) * t
            }
            completion?()
        }
    }

    // MARK: - 噪声合成

    private func buildGraph() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let source = Self.makeNoiseNode(format: format)
        let eq = Self.makeScratchEQ()

        engine.attach(source)
        engine.attach(eq)
        engine.attach(mixer)
        engine.connect(source, to: eq, format: format)
        engine.connect(eq, to: mixer, format: format)
        engine.connect(mixer, to: engine.mainMixerNode, format: format)
        mixer.outputVolume = 0
    }

    /// 白噪声源 + 一条缓慢摆动的幅度包络，让声音听起来像断续的运笔摩擦，而不是一段平稳的底噪。
    /// xorshift 生成噪声（比 Swift 默认 RNG 更适合实时音频回调：无锁、无堆分配、够快）。
    private static func makeNoiseNode(format: AVAudioFormat) -> AVAudioSourceNode {
        var seed: UInt32 = 0x2F6E_2B15
        var phase: Float = 0
        let sampleRate = Float(format.sampleRate)

        return AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                seed ^= seed << 13
                seed ^= seed >> 17
                seed ^= seed << 5
                // 只随机化尾数位（保留 1.0 的符号/指数位）得到 [1, 2)，再映射到 [-1, 1) 均匀分布
                let raw = Float(bitPattern: 0x3F80_0000 | (seed >> 9))
                let white = (raw - 1.0) * 2.0 - 1.0

                phase += 1.0 / sampleRate
                if phase > 1 { phase -= 1 }
                let envelope = 0.55 + 0.45 * sinf(phase * 2 * .pi * 7)   // ~7Hz 起伏，模拟运笔节奏

                let sample = white * envelope
                for buffer in abl {
                    guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    data[frame] = sample
                }
            }
            return noErr
        }
    }

    /// 带通滤波：切掉低频隆隆声与高频刺耳声，中频提升出纸张摩擦感。
    private static func makeScratchEQ() -> AVAudioUnitEQ {
        let eq = AVAudioUnitEQ(numberOfBands: 3)

        let highPass = eq.bands[0]
        highPass.filterType = .highPass
        highPass.frequency = 700
        highPass.bypass = false

        let peak = eq.bands[1]
        peak.filterType = .parametric
        peak.frequency = 3200
        peak.bandwidth = 1.2
        peak.gain = 6
        peak.bypass = false

        let lowPass = eq.bands[2]
        lowPass.filterType = .lowPass
        lowPass.frequency = 6500
        lowPass.bypass = false

        return eq
    }
}
