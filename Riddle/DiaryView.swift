import SwiftUI
import PencilKit

struct DiaryView: View {
    @State private var canvasView = PKCanvasView()
    @State private var overlayHost = OverlayHostView()
    @State private var engine: TurnEngine?

    var body: some View {
        ZStack {
            Color(Ink.paperColor).ignoresSafeArea()
            RadialGradient(colors: [.clear, .black.opacity(0.08)],
                           center: .center, startRadius: 200, endRadius: 900)
                .ignoresSafeArea().allowsHitTesting(false)
            InkCanvas(canvasView: canvasView) { drawing in
                engine?.drawingChanged(drawing)
            }
            .ignoresSafeArea()
            OverlayHost(view: overlayHost).ignoresSafeArea().allowsHitTesting(false)
        }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
        .onAppear {
            if engine == nil {
                engine = TurnEngine(canvasView: canvasView, overlayHost: overlayHost)
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
