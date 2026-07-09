import AVFoundation
import QuartzCore

/// 笔尖书写音效：合成噪声经带通滤波，模拟纸上运笔的沙沙声。零素材、纯代码合成——
/// 不需要采买/授权任何音频文件，也没有额外的 App 体积开销。
///
/// 音频会话用 `.ambient`：遵守静音键（用户静音时天然不发声）、与其他 App 的音频混音
/// （不会打断用户正在放的音乐），这是日记类 App 的底线要求。
///
/// 门控：每次 `start()` 都先查 `SoundStore.isEnabled`，关闭时整个引擎都不会被触碰
/// （见 `shouldPlay()`，一个不依赖引擎状态的纯判断，方便单测）。
///
/// 音量不再是「落笔到抬笔之间的一段固定强度」，而是持续跟随笔速：`updateVelocity(_:)`
/// 由 `InkCanvas`（真实笔速，来自 `PKStrokePath` 相邻采样点的位移/时间差）与 `QuillLayer`
/// （AI 落笔动画，每一笔喂一次带抖动的额定速度）共同驱动，详见各自调用处的注释。
@MainActor
final class PenSound {
    static let shared = PenSound()

    // MARK: - 调这三个就够（不用改下面的合成逻辑）

    /// 整体音量天花板：所有颗粒声音的最终倍率。数值越大越吵，0 就是彻底静音。
    /// 默认压得很低——这是锦上添花的底噪，不能抢戏。
    static let baseVolume: Float = 0.09

    /// 颗粒密度换算：笔速归一化强度（0...1）→ 每秒颗粒数。数值越大，快速运笔时颗粒
    /// 越密集越"沙沙"；调小会让整体声音更稀疏、更克制。这是本次修复的核心——
    /// 旧版本没有这个量，是恒定 7Hz 的抖动，跟笔速毫无关系。
    static let grainDensityScale: Float = 90

    /// 摩擦声主观明亮度的中心频率（Hz）。数值越低声音越闷/越像纸张摩擦，越高越像刺耳的沙沙声。
    /// 高通/低通两个边界会按比例跟着它一起挪，相当于整条频带左右平移，一个数就能调音色。
    static let filterCenterHz: Float = 2200

    // MARK: - 内部实现参数（一般不用碰）

    private static let maxSpeedPtsPerSecond: CGFloat = 1400   // 笔速归一化的上限，超过就按满强度算
    private static let pauseThreshold: CFTimeInterval = 0.12  // 触纸但超过这个时长没收到新笔速→判定为暂停
    private static let idleWatchdogTickNanos: UInt64 = 60_000_000
    private static let grainVoiceCount = 6                    // 允许同时叠加的颗粒数（做出疏密不均的质感）
    private static let grainMinMs: Float = 3
    private static let grainMaxMs: Float = 14
    private static let intensitySmoothingTau: Float = 0.05    // 强度参数的平滑时间常数，避免"啪"一下跳变

    private let store: SoundStore
    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()

    /// 笔速强度参数：主线程写（`updateVelocity`/空闲看门狗），实时音频渲染线程读。
    private let intensity = PenSoundIntensity()

    /// 引擎当前是否处于「正在发声/淡入中」的逻辑活跃态——不等价于 `engine.isRunning`
    /// （停止时先淡出、淡出完成才真正 pause 引擎），供 `stop()` 内部判断与测试断言使用。
    private(set) var isActive = false

    private var fadeTask: Task<Void, Never>?
    private var idleWatchdog: Task<Void, Never>?
    private var lastVelocityUpdate: CFTimeInterval = 0

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
    ///
    /// 注意：`start()` 本身不产生声音强度——强度完全由后续的 `updateVelocity(_:)` 驱动。
    /// 这正是「刚触纸尚未移动时应当近乎无声」的来源，不需要额外的特判。
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
        lastVelocityUpdate = CACurrentMediaTime()   // 给第一次笔速采样一个宽限窗口，别立刻被看门狗判定为空闲
        startIdleWatchdog()
        rampVolume(to: 1.0, seconds: fadeInSeconds)
    }

    /// 停止书写：笔尖离开纸面/QuillLayer 一句写完时调用。淡出后暂停引擎（不是彻底 stop），
    /// 下次 `start()` 可以立即续上，没有引擎冷启动的延迟。
    func stop() {
        fadeTask?.cancel()
        idleWatchdog?.cancel()
        isActive = false
        intensity.value = 0   // 立即把目标强度归零，颗粒会在 DSP 的平滑窗口内自然淡出，不会咔一声切断
        rampVolume(to: 0, seconds: fadeOutSeconds) { [weak self] in
            guard let self, !self.isActive else { return }   // 淡出途中又被 start() 抢占，别误停
            if self.engine.isRunning { self.engine.pause() }
        }
    }

    /// 供 `InkCanvas`（真实笔速，来自 `PKStrokePath` 相邻采样点）与 `QuillLayer`
    /// （AI 落笔动画，每一笔一个带抖动的额定速度）调用：喂入这一刻的运笔速度（点/秒），
    /// 驱动颗粒密度与颗粒响度。只在 `isActive` 时生效——引擎没在播放就不用管这些数字。
    func updateVelocity(_ pointsPerSecond: CGFloat) {
        guard isActive else { return }
        lastVelocityUpdate = CACurrentMediaTime()
        intensity.value = Self.normalizedIntensity(forSpeed: pointsPerSecond)
    }

    /// 纯函数、不碰引擎：笔速(pt/s) → 归一化强度 [0,1]。这是本次改动里唯一能脱离
    /// `AVAudioEngine` 单测的逻辑，专门抽出来就是为了能在 XCTest 里覆盖它。
    /// 用 0.7 次幂做一条轻微上凸的响度曲线：低速段不会哑得太快，高速段在上限处封顶到 1。
    static func normalizedIntensity(forSpeed pointsPerSecond: CGFloat) -> Float {
        guard pointsPerSecond.isFinite, pointsPerSecond > 0 else { return 0 }
        let clamped = min(pointsPerSecond, maxSpeedPtsPerSecond)
        let linear = Float(clamped / maxSpeedPtsPerSecond)
        return powf(linear, 0.7)
    }

    /// 空闲看门狗：笔还按在纸面上、但已经有一阵子没收到新的笔速采样（用户停笔不动、或
    /// AI 两句之间的间隙）时，主动把目标强度摁回 0——不然停笔不动时会一直响着上一刻的音量。
    /// 只做「设定目标为 0」这一件事，真正的音量渐变交给渲染回调里的平滑滤波，不会有咔哒声。
    private func startIdleWatchdog() {
        idleWatchdog?.cancel()
        idleWatchdog = Task { [weak self] in
            while let self, !Task.isCancelled, self.isActive {
                try? await Task.sleep(nanoseconds: Self.idleWatchdogTickNanos)
                guard !Task.isCancelled, self.isActive else { return }
                if CACurrentMediaTime() - self.lastVelocityUpdate > Self.pauseThreshold {
                    self.intensity.value = 0
                }
            }
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
        let source = Self.makeGrainNoiseNode(format: format, intensity: intensity)
        let eq = Self.makeScratchEQ()

        engine.attach(source)
        engine.attach(eq)
        engine.attach(mixer)
        engine.connect(source, to: eq, format: format)
        engine.connect(eq, to: mixer, format: format)
        engine.connect(mixer, to: engine.mainMixerNode, format: format)
        mixer.outputVolume = 0
    }

    /// 不规则摩擦颗粒噪声源：不再是「白噪声 + 恒定 7Hz 幅度抖动」（那是问题报告里"像筛子"的
    /// 根因——听感是一个稳定的机械律动，而不是运笔摩擦）。
    ///
    /// 改成颗粒合成（granular synthesis）：每个采样点按当前笔速强度换算出的概率，随机触发一枚
    /// 短促的噪声颗粒（3~14ms，快起快落的包络），多枚颗粒可以叠加，密度和响度都跟着
    /// `intensity`（由 `updateVelocity` 驱动）走——笔速快→颗粒又密又响，笔速慢→稀疏轻声，
    /// 停笔不动→（经由空闲看门狗）趋于无声。触发时刻本身是随机的，这就是"不规则"的来源，
    /// 读起来是摩擦颗粒感，而不是有节奏的筛动。
    ///
    /// xorshift 生成随机数（比 Swift 默认 RNG 更适合实时音频回调：无锁、无堆分配、够快）。
    private static func makeGrainNoiseNode(format: AVAudioFormat, intensity: PenSoundIntensity) -> AVAudioSourceNode {
        var seed: UInt32 = 0x2F6E_2B15
        let sampleRate = Float(format.sampleRate)
        let smoothCoeff = 1 - expf(-(1 / sampleRate) / intensitySmoothingTau)

        var smoothedIntensity: Float = 0
        var voiceRemaining = [Int](repeating: 0, count: grainVoiceCount)
        var voiceLength = [Int](repeating: 1, count: grainVoiceCount)
        var voiceAmp = [Float](repeating: 0, count: grainVoiceCount)
        var voiceCursor = 0

        func nextUnitFloat() -> Float {
            seed ^= seed << 13
            seed ^= seed >> 17
            seed ^= seed << 5
            // 只随机化尾数位（保留 1.0 的符号/指数位）得到 [1, 2)，再映射到 [0, 1)
            let raw = Float(bitPattern: 0x3F80_0000 | (seed >> 9))
            return raw - 1.0
        }

        func grainEnvelope(_ progress: Float) -> Float {
            let attack: Float = 0.12   // 快起
            if progress < attack {
                return progress / attack
            }
            let decayProgress = (progress - attack) / (1 - attack)
            let fall = 1 - decayProgress
            return fall * fall          // 慢一点的平方衰减，读起来像摩擦颗粒而不是敲击声
        }

        return AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let targetIntensity = intensity.value

            for frame in 0..<Int(frameCount) {
                smoothedIntensity += (targetIntensity - smoothedIntensity) * smoothCoeff

                // 每采样点按当前强度换算出的密度，用一次随机抽样判定是否触发新颗粒——
                // 这是不规则触发（而非固定周期）的关键，读起来是摩擦粒感而不是节拍。
                let grainsPerSecond = grainDensityScale * smoothedIntensity
                let triggerProbability = grainsPerSecond / sampleRate
                if triggerProbability > 0, nextUnitFloat() < triggerProbability {
                    voiceCursor = (voiceCursor + 1) % grainVoiceCount
                    let durationMs = grainMinMs + nextUnitFloat() * (grainMaxMs - grainMinMs)
                    let length = max(Int(durationMs / 1000 * sampleRate), 1)
                    voiceLength[voiceCursor] = length
                    voiceRemaining[voiceCursor] = length
                    voiceAmp[voiceCursor] = 0.55 + nextUnitFloat() * 0.45   // 每颗粒响度也随机抖一下，避免颗粒感太均匀
                }

                var grainSum: Float = 0
                for v in 0..<grainVoiceCount where voiceRemaining[v] > 0 {
                    let progress = 1 - Float(voiceRemaining[v]) / Float(voiceLength[v])
                    let white = nextUnitFloat() * 2 - 1
                    grainSum += white * grainEnvelope(progress) * voiceAmp[v]
                    voiceRemaining[v] -= 1
                }

                // 归一化：最多 grainVoiceCount 枚颗粒同时叠加，但实际同时活跃的很少，
                // 除以一个保守的常数避免叠加时顶到爆音；最终响度上限交给 baseVolume 调。
                let sample = (grainSum / 3) * baseVolume
                for buffer in abl {
                    guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    data[frame] = sample
                }
            }
            return noErr
        }
    }

    /// 带通滤波：切掉低频隆隆声与高频刺耳声，中频提升出纸张摩擦感。三个频段都按
    /// `filterCenterHz` 成比例挪动，一个数就能把整条频带左右平移；相比旧版本，中心
    /// 频率更低、共振带更宽、增益更低——避免出现让人联想到"筛子"的窄带共振尖峰。
    private static func makeScratchEQ() -> AVAudioUnitEQ {
        let eq = AVAudioUnitEQ(numberOfBands: 3)

        let highPass = eq.bands[0]
        highPass.filterType = .highPass
        highPass.frequency = filterCenterHz * 0.32
        highPass.bypass = false

        let peak = eq.bands[1]
        peak.filterType = .parametric
        peak.frequency = filterCenterHz
        peak.bandwidth = 1.8
        peak.gain = 4
        peak.bypass = false

        let lowPass = eq.bands[2]
        lowPass.filterType = .lowPass
        lowPass.frequency = filterCenterHz * 3.0
        lowPass.bypass = false

        return eq
    }
}

/// 实时音频渲染线程与主线程之间共享的强度参数：写者是主线程（`updateVelocity`/空闲看门狗），
/// 读者是 `AVAudioSourceNode` 的渲染回调。用一把轻量锁而不是引入额外的原子库依赖——
/// 这里只是一个连续渐变的音量参数，不追求跨线程强一致，读到"最近写过的某个值"完全够用，
/// 且写入频率远低于音频采样率，锁竞争可以忽略不计。
private final class PenSoundIntensity: @unchecked Sendable {
    private var storage: Float = 0
    private let lock = NSLock()

    var value: Float {
        get { lock.lock(); defer { lock.unlock() }; return storage }
        set { lock.lock(); defer { lock.unlock() }; storage = newValue }
    }
}
