import SwiftUI

@main
struct RiddleApp: App {
    @MainActor
    init() {
        // 手泽（SDT 轨迹字库）常驻内存一次；缺文件/损坏时 preload 内部吞下失败，bank(for:) 返回 nil，
        // QuillLayer/HandPickerView 全部回落字体，无需在此处理错误。
        // 异步后台加载（两次 gunzip + 13,526 条记录 JSON 解码，解压后共 ~2.7MB），避免阻塞冷启动首帧；
        // 加载完成前的任何渲染调用都会看到 bank(for:) 仍是 nil，天然落到已有的字体回落分支。
        if let bankStyle = ReplyHands.shouze.bankStyle {
            Task.detached(priority: .userInitiated) {
                await HandBankStore.shared.preloadAsync(style: bankStyle)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// 每次冷启动都是开门仪式：先圈选角色，再进入日记纸面；圈住纸角落款可随时合上本子、回到圈选页。
/// 圈选后 DiaryView 本身的写作逻辑不受影响——只是多了一条 onReturnToPicker 出口。
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
                DiaryView {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        phase = .picking
                    }
                }
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
