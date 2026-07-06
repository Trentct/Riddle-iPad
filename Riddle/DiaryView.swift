import SwiftUI
import PencilKit

struct DiaryView: View {
    private let canvasView = PKCanvasView()
    private let overlayHost = OverlayHostView()
    @State private var idleTimer: Timer?

    var body: some View {
        ZStack {
            Color(Ink.paperColor).ignoresSafeArea()
            RadialGradient(colors: [.clear, .black.opacity(0.08)],
                           center: .center, startRadius: 200, endRadius: 900)
                .ignoresSafeArea().allowsHitTesting(false)
            InkCanvas(canvasView: canvasView) { drawing in
                idleTimer?.invalidate()
                guard !drawing.strokes.isEmpty else { return }
                idleTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                    let bounds = canvasView.bounds
                    let snapshot = canvasView.drawing
                    canvasView.drawing = PKDrawing()
                    FadeLayer.drink(snapshot, in: overlayHost, bounds: bounds) {}
                }
            }
            .ignoresSafeArea()
            OverlayHost(view: overlayHost).ignoresSafeArea().allowsHitTesting(false)
        }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
        // TODO(Task 10): remove verification hook
        .onTapGesture(count: 3) {
            let quill = QuillLayer(host: overlayHost, pageBounds: overlayHost.bounds)
            quill.write("Harry Potter — an interesting name indeed.") {
                quill.write("哈利·波特，真是个有趣的名字。") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { quill.fadeOutAll {} }
                }
            }
        }
    }
}

final class OverlayHostView: UIView {}

struct OverlayHost: UIViewRepresentable {
    let view: OverlayHostView
    func makeUIView(context: Context) -> OverlayHostView { view }
    func updateUIView(_ uiView: OverlayHostView, context: Context) {}
}
