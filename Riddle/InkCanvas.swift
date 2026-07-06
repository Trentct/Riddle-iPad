import SwiftUI
import PencilKit

enum Ink {
    static let userColor = UIColor(red: 0x1A / 255, green: 0x1A / 255, blue: 0x2E / 255, alpha: 1)
    static let quillColor = UIColor(red: 0x0F / 255, green: 0x0F / 255, blue: 0x23 / 255, alpha: 1)
    static let paperColor = UIColor(red: 0xF2 / 255, green: 0xED / 255, blue: 0xE1 / 255, alpha: 1)
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
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onDrawingChanged) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let onChange: (PKDrawing) -> Void
        init(onChange: @escaping (PKDrawing) -> Void) { self.onChange = onChange }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onChange(canvasView.drawing)
        }
    }
}
