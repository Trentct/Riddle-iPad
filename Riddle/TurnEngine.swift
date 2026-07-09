import UIKit
import PencilKit

/// 回合状态机：所有模块的唯一协调者。
@MainActor
final class TurnEngine {
    enum State { case idle, writing, drinking, replying, lingering }
    private(set) var state: State = .idle

    private let canvasView: PKCanvasView
    private let overlayHost: UIView
    private let oracle = Oracle()
    private let usageStore: UsageStore
    private var quill: QuillLayer?
    private var idleTimer: Timer?
    private var lingerTask: Task<Void, Never>?
    private var replyTask: Task<Void, Never>?
    /// 回合代号：抢占时自增，旧回合的异步续体自检后静默退场。
    private var turnID = 0

    /// 配额耗尽时触发（客户端免费额度用尽，或后端返回 402）——由持有者（DiaryView）设置，
    /// 用来弹出付费页；TurnEngine 本身不知道 UI 怎么展示，只负责在正确的时机喊一声。
    var onQuotaExceeded: (() -> Void)?

    static let idleInterval: TimeInterval = 1.8
    static let lingerSeconds: TimeInterval = 5

    /// `usageStore` 默认 nil，在方法体内（已经在 MainActor 上）才落到 `.shared`——同样的理由见
    /// Oracle.init 的 historyStore：默认参数表达式本身在非隔离上下文求值，不能直接引用 @MainActor 静态属性。
    init(canvasView: PKCanvasView, overlayHost: UIView, usageStore: UsageStore? = nil) {
        self.canvasView = canvasView
        self.overlayHost = overlayHost
        self.usageStore = usageStore ?? .shared
    }

    /// InkCanvas 每次笔迹变化时调用。
    func drawingChanged(_ drawing: PKDrawing) {
        idleTimer?.invalidate()
        guard !drawing.strokes.isEmpty else { return }

        // 用户落笔优先：作废在途回合（含等待回信中），残留回信立即让位
        if state == .lingering || state == .replying || state == .drinking {
            turnID += 1
            replyTask?.cancel()
            replyTask = nil
            lingerTask?.cancel()
            lingerTask = nil
            quill?.fadeOutAll {}
            quill = nil
            state = .writing
        }
        if state == .idle { state = .writing }
        guard state == .writing else { return }

        idleTimer = Timer.scheduledTimer(withTimeInterval: Self.idleInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.commitPage() }
        }
    }

    private func commitPage() {
        guard state == .writing else { return }
        // 免费额度门控：在真正提交这一页（drink 动画、发给模型）之前检查，用户的笔迹原样留在纸上，
        // 不消耗、不发送——只是让回信让位给付费页。
        guard usageStore.canSendReply else {
            state = .idle
            onQuotaExceeded?()
            return
        }
        state = .drinking
        let bounds = canvasView.bounds
        let drawing = canvasView.drawing
        guard !drawing.strokes.isEmpty else { state = .idle; return }

        // 整页 PNG（纸色底 + 笔迹），供模型阅读
        let png = renderPage(drawing, bounds: bounds)
        canvasView.drawing = PKDrawing()
        FadeLayer.drink(drawing, in: overlayHost, bounds: bounds) {}

        let quill = QuillLayer(host: overlayHost, pageBounds: bounds)
        self.quill = quill
        turnID += 1
        let myTurn = turnID

        replyTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var replyText = ""
            do {
                var first = true
                for try await sentence in self.oracle.ask(pagePNG: png) {
                    guard self.turnID == myTurn else { return }   // 回合已被抢占
                    if first { self.state = .replying; first = false }
                    replyText += sentence
                    await withCheckedContinuation { cont in
                        quill.write(sentence) { cont.resume() }
                    }
                    guard self.turnID == myTurn else { return }
                }
                guard self.turnID == myTurn else { return }
                self.oracle.recordReply(replyText)
                self.usageStore.recordReply()
                self.startLinger(for: myTurn)
            } catch OracleError.quotaExceeded {
                // 配额耗尽（防御性：本地门控放过了但服务端拒绝，或后端模式下服务端先一步发现）——
                // 让位给付费页，不在人设内写错误字，也不进入 lingering。
                guard self.turnID == myTurn else { return }
                quill.fadeOutAll {}
                self.quill = nil
                self.state = .idle
                self.onQuotaExceeded?()
            } catch {
                // 抢占取消不写错误字；真实失败才在人设内表达
                guard self.turnID == myTurn else { return }
                await withCheckedContinuation { cont in
                    quill.write("墨迹晕开了，什么也没显现……") { cont.resume() }
                }
                guard self.turnID == myTurn else { return }
                self.startLinger(for: myTurn)
            }
        }
    }

    private func startLinger(for turn: Int) {
        guard turnID == turn else { return }
        state = .lingering
        lingerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.lingerSeconds))
            guard let self, !Task.isCancelled, self.turnID == turn else { return }
            self.quill?.fadeOutAll {}
            self.quill = nil
            self.state = .idle
        }
    }

    private func renderPage(_ drawing: PKDrawing, bounds: CGRect) -> Data {
        // scale 1（而非默认屏幕 2×）+ JPEG：手写页是纯色底 + 稀疏墨迹，PNG@2x 约 360KB，
        // 让 Moonshot 识图慢到数秒、上传也大；scale1 JPEG q0.6 降到几十 KB，识图/上传/token 全省。
        // 识别手写只需可读分辨率，1× 足够。
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        let image = renderer.image { ctx in
            Ink.paperColor.setFill()
            ctx.fill(bounds)
            drawing.image(from: bounds, scale: 1).draw(in: bounds)
        }
        return image.jpegData(compressionQuality: 0.6) ?? Data()
    }
}
