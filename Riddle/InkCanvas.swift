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
        canvasView.drawingPolicy = .anyInput   // 模拟器鼠标可画；真机拍摄时可改 .pencilOnly
        canvasView.delegate = context.coordinator
        canvasView.isScrollEnabled = false     // PKCanvasView 是 UIScrollView 子类，禁掉内容滚动/缩放，避免双指手势被吞

        let swipeLeft = UISwipeGestureRecognizer(target: context.coordinator,
                                                  action: #selector(Coordinator.handleSwipeLeft))
        swipeLeft.direction = .left
        swipeLeft.numberOfTouchesRequired = 2
        swipeLeft.delegate = context.coordinator
        canvasView.addGestureRecognizer(swipeLeft)

        let swipeRight = UISwipeGestureRecognizer(target: context.coordinator,
                                                   action: #selector(Coordinator.handleSwipeRight))
        swipeRight.direction = .right
        swipeRight.numberOfTouchesRequired = 2
        swipeRight.delegate = context.coordinator
        canvasView.addGestureRecognizer(swipeRight)

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

        // 双指左滑 = 下一款纸，右滑 = 上一款纸，环绕切换
        @objc func handleSwipeLeft() { cycle(1) }
        @objc func handleSwipeRight() { cycle(-1) }

        private func cycle(_ direction: Int) {
            PaperStyleStore.shared.cycle(direction)
            // 新笔迹立即使用新纸的用户墨色；已画的旧笔迹不回溯变色
            canvasView?.tool = PKInkingTool(.pen, color: PaperStyleStore.shared.current.userInk, width: 3)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }
    }
}
