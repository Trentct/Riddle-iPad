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

/// 每次冷启动都是开门仪式：先在书架上取一本书（选角色），再进入日记纸面；圈住纸角落款可随时合上
/// 本子、回到书架。选书后 DiaryView 本身的写作逻辑不受影响——只是多了一条 onReturnToPicker 出口。
/// `.picking` 相位现由 `BookshelfView`（三本书立在书桌上）承载；`HandPickerView`（旧的圈选三行字）
/// 保留在文件里未删除，只是不再路由到它——留给作为后备。
///
/// 翻开转场（Task 2）：`bookNS` 是共享的 matchedGeometryEffect 命名空间，`selectedHand` 记住被点的
/// 那本书。`.picking`/`.writing` 用 switch 互斥呈现（同一 transaction 内一边消失一边出现，这正是
/// matchedGeometryEffect 的经典用法——被点的书封与书写页容器共用同一个 `id: hand.id`，SwiftUI 据此把
/// 帧从"书架上的小书封"插值放大到"全屏纸页"）。书封内容 fade-out（BookshelfView 整体 `.opacity`
/// 转场）与纸页 fade-in（`.opacity` 转场）天然叠加在放大的帧上，读出来是"翻开"而不是硬切/硬缩放。
/// 返回：DiaryView 圈落款回调复用同一条 withAnimation spring，反向播放同一段转场回书架。
struct RootView: View {
    enum Phase { case picking, writing }
    @State private var phase: Phase = .picking
    @State private var selectedHand: ReplyHand?
    @Namespace private var bookNS

    private static let openAnimation = Animation.spring(response: 0.55, dampingFraction: 0.82)

    var body: some View {
        ZStack {
            switch phase {
            case .picking:
                BookshelfView(bookNS: bookNS) { hand in
                    selectedHand = hand
                    ReplyHandStore.shared.select(hand.id)
                    withAnimation(Self.openAnimation) {
                        phase = .writing
                    }
                }
                .transition(.opacity)
            case .writing:
                if let hand = selectedHand {
                    DiaryView {
                        withAnimation(Self.openAnimation) {
                            phase = .picking
                        }
                    }
                    .matchedGeometryEffect(id: hand.id, in: bookNS)
                    .transition(.opacity)
                }
            }
        }
    }
}

enum Secrets {
    static var apiKey: String { Bundle.main.object(forInfoDictionaryKey: "MOONSHOT_API_KEY") as? String ?? "" }
    static var baseURL: String { Bundle.main.object(forInfoDictionaryKey: "MOONSHOT_BASE_URL") as? String ?? "" }
    static var model: String { Bundle.main.object(forInfoDictionaryKey: "MOONSHOT_MODEL") as? String ?? "" }
    /// riddle-backend 代理地址与 App 级共享密钥（软保护，见 riddle-backend README "Security honest-truth"）——
    /// 只在 AppConfig.useBackend 为 true 时使用，dev 默认路径不读取这两个值。
    static var backendURL: String { Bundle.main.object(forInfoDictionaryKey: "BACKEND_URL") as? String ?? "" }
    static var appSharedSecret: String { Bundle.main.object(forInfoDictionaryKey: "APP_SHARED_SECRET") as? String ?? "" }
}
