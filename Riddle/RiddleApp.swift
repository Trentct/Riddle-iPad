import SwiftUI

@main
struct RiddleApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// 每次冷启动都是开门仪式：先圈选笔迹，再进入日记纸面。
/// 圈选后 DiaryView 不受影响——本文件外任何写作逻辑无需感知这道相位切换。
struct RootView: View {
    enum Phase { case picking, writing }
    @State private var phase: Phase = .picking

    var body: some View {
        ZStack {
            switch phase {
            case .picking:
                HandPickerView { hand in
                    ReplyHandStore.shared.select(hand.id)
                    withAnimation(.easeInOut(duration: 0.35)) {
                        phase = .writing
                    }
                }
                .transition(.opacity)
            case .writing:
                DiaryView()
                    .transition(.opacity)
            }
        }
    }
}

enum Secrets {
    static var apiKey: String { Bundle.main.object(forInfoDictionaryKey: "MOONSHOT_API_KEY") as? String ?? "" }
    static var baseURL: String { Bundle.main.object(forInfoDictionaryKey: "MOONSHOT_BASE_URL") as? String ?? "" }
    static var model: String { Bundle.main.object(forInfoDictionaryKey: "MOONSHOT_MODEL") as? String ?? "" }
}
