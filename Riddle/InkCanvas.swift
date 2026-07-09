import SwiftUI
import PencilKit

/// 单一取色入口：始终读取当前纸张样式的墨色/纸色，QuillLayer/TurnEngine 无需感知样式切换。
enum Ink {
    static var userColor: UIColor { PaperStyleStore.shared.current.userInk }
    static var quillColor: UIColor { PaperStyleStore.shared.current.quillInk }
    static var paperColor: UIColor { PaperStyleStore.shared.current.paperColor }
}

struct InkCanvas: UIViewRepresentable {
    let canvasView: PKCanvasView
    var onDrawingChanged: (PKDrawing) -> Void

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.tool = PKInkingTool(.pen, color: Ink.userColor, width: 3)
        #if targetEnvironment(simulator)
        canvasView.drawingPolicy = .anyInput    // 模拟器鼠标可画
        #else
        canvasView.drawingPolicy = .pencilOnly  // 真机仅 Pencil：双指手势永不误触发笔迹
        #endif
        canvasView.delegate = context.coordinator
        canvasView.isScrollEnabled = false     // PKCanvasView 是 UIScrollView 子类，禁掉内容滚动/缩放，避免双指手势被吞

        // 双指翻纸：用 Pan（连续型，手势仲裁中比 Swipe 可靠）+ 手动判定横扫。
        // Swipe 识别器挂在 PKCanvasView 上会被其内部手势仲裁饿死（真机上永不触发）。
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTwoFingerPan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.allowedTouchTypes = [UITouch.TouchType.direct.rawValue as NSNumber]  // 仅手指，不抢 Pencil
        pan.delegate = context.coordinator
        canvasView.addGestureRecognizer(pan)

        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(canvasView: canvasView, onChange: onDrawingChanged) }

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
        let onChange: (PKDrawing) -> Void
        private weak var canvasView: PKCanvasView?

        init(canvasView: PKCanvasView, onChange: @escaping (PKDrawing) -> Void) {
            self.canvasView = canvasView
            self.onChange = onChange
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onChange(canvasView.drawing)
        }

        // 双指横扫判定：位移超阈值且以横向为主 → 翻纸。每次手势只翻一次。
        private var panConsumed = false

        @objc func handleTwoFingerPan(_ gr: UIPanGestureRecognizer) {
            switch gr.state {
            case .began:
                panConsumed = false
            case .changed:
                guard !panConsumed, let view = gr.view else { return }
                let t = gr.translation(in: view)
                guard abs(t.x) > 60, abs(t.x) > 2 * abs(t.y) else { return }
                panConsumed = true
                cycle(t.x < 0 ? 1 : -1)   // 左滑下一款，右滑上一款
            default:
                break
            }
        }

        private func cycle(_ direction: Int) {
            PaperStyleStore.shared.cycle(direction)
            // 新笔迹立即使用新纸的用户墨色；已画的旧笔迹不回溯变色
            canvasView?.tool = PKInkingTool(.pen, color: PaperStyleStore.shared.current.userInk, width: 3)
        }

        // 与 PKCanvasView 内部识别器并存，不参与互斥仲裁——这是双指手势在画布上能收到事件的关键。
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
