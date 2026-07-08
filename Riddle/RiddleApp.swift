import SwiftUI

@main
struct RiddleApp: App {
    @MainActor
    init() {
        // 手泽（SDT 轨迹字库）常驻内存一次；缺文件/损坏时 preload 内部吞下失败，bank(for:) 返回 nil，
        // QuillLayer/HandPickerView 全部回落字体，无需在此处理错误。
        if let bankStyle = ReplyHands.shouze.bankStyle {
            HandBankStore.shared.preload(style: bankStyle)
        }
    }

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
