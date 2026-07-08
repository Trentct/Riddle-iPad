import Foundation

/// 书写笔尖音效的开关：默认开启，持久化到 UserDefaults。目前没有设置 UI——
/// 未来的「关于/设置」页只需读写 `isEnabled`/`setEnabled` 即可接上开关；`PenSound` 在每次
/// 播放前读取本 store 做门控。与 `OnboardingStore`/`PaperStyleStore` 同一套持久化模式：
/// `shared` 单例 + 可注入 `UserDefaults` 便于测试隔离。仅主线程访问 —— @MainActor 保证。
@MainActor
final class SoundStore: ObservableObject {
    static let shared = SoundStore()
    static let defaultsKey = "penSoundEnabled"

    @Published private(set) var isEnabled: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 默认开启：未设置过时不能用 `defaults.bool(forKey:)` 的天然 false 默认值（那是给
        // OnboardingStore 那种「默认关」用的），这里必须显式判断 key 是否存在过。
        if defaults.object(forKey: Self.defaultsKey) == nil {
            self.isEnabled = true
        } else {
            self.isEnabled = defaults.bool(forKey: Self.defaultsKey)
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.defaultsKey)
    }

    func toggle() {
        setEnabled(!isEnabled)
    }
}
