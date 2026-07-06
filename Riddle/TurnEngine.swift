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
    private var quill: QuillLayer?
    private var idleTimer: Timer?
    private var lingerTask: Task<Void, Never>?
    private var replyTask: Task<Void, Never>?
    /// 回合代号：抢占时自增，旧回合的异步续体自检后静默退场。
    private var turnID = 0

    static let idleInterval: TimeInterval = 2.8
    static let lingerSeconds: TimeInterval = 8

    init(canvasView: PKCanvasView, overlayHost: UIView) {
        self.canvasView = canvasView
        self.overlayHost = overlayHost
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
                self.startLinger(for: myTurn)
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
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.pngData { ctx in
            Ink.paperColor.setFill()
            ctx.fill(bounds)
            drawing.image(from: bounds, scale: 2).draw(in: bounds)
        }
    }
}
