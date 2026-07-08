import Foundation

/// 后端可切换开关：默认直连 Moonshot（dev 默认，冒烟测试路径不变），USE_BACKEND=YES 时
/// 切到 riddle-backend 代理（生产路径，key 不再随 App 出货）。值来自 Info.plist（xcconfig 注入）。
enum AppConfig {
    static var useBackend: Bool {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "USE_BACKEND") as? String ?? "NO")
            .trimmingCharacters(in: .whitespaces)
        return raw.uppercased() == "YES" || raw.uppercased() == "TRUE" || raw == "1"
    }
}
