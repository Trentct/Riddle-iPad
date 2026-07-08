import Foundation

/// 匿名设备号：后端按 `X-Device-Id` 做每日免费额度限流。UserDefaults 持久化——重装会拿到新
/// 设备号（等于免费额度重置），这是有意的权衡（见 riddle-backend/docs/APP_INTEGRATION.md 第 2 节）。
enum DeviceId {
    private static let key = "riddle.deviceId"

    static var current: String {
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }
}
