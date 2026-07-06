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
    private var replyText = ""

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

        // 用户落笔优先：残留的回信立即让位
        if state == .lingering || state == .replying {
            lingerTask?.cancel()
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
        self.replyText = ""

        Task { @MainActor in
            do {
                var first = true
                for try await sentence in oracle.ask(pagePNG: png) {
                    if first { state = .replying; first = false }
                    replyText += sentence
                    await withCheckedContinuation { cont in
                        quill.write(sentence) { cont.resume() }
                    }
                }
                oracle.recordReply(replyText)
                startLinger()
            } catch {
                // 错误也在人设内：手写浮现一行小字
                await withCheckedContinuation { cont in
                    quill.write("墨迹晕开了，什么也没显现……") { cont.resume() }
                }
                startLinger()
            }
        }
    }

    private func startLinger() {
        state = .lingering
        lingerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.lingerSeconds))
            guard let self, !Task.isCancelled else { return }
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
