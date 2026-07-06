import SwiftUI
import PencilKit

struct DiaryView: View {
    @State private var canvasView = PKCanvasView()
    @State private var overlayHost = OverlayHostView()
    @State private var engine: TurnEngine?
    @ObservedObject private var paperStore = PaperStyleStore.shared

    var body: some View {
        let style = paperStore.current
        ZStack {
            Group {
                Color(style.paperColor).ignoresSafeArea()

                if style.ruled {
                    RuledLinesView()
                        .ignoresSafeArea()
                        .transition(.opacity)
                }

                Image(uiImage: PaperTexture.tile)
                    .resizable(resizingMode: .tile)
                    .opacity(style.noiseOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                if style.riceFiber {
                    Image(uiImage: PaperTexture.fiberTile)
                        .resizable(resizingMode: .tile)
                        .opacity(0.03)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                RadialGradient(colors: [.clear, .black.opacity(style.vignetteOpacity)],
                               center: .center, startRadius: 200, endRadius: 900)
                    .ignoresSafeArea().allowsHitTesting(false)
            }
            .animation(.easeInOut(duration: 0.35), value: style.id)

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

/// 横线信纸背景：蓝灰横线（自 pageHeight/3 起，间距 44pt，与 QuillLayer 回信行高对齐）+ 红色装订边线。
struct RuledLinesView: View {
    var body: some View {
        Canvas { context, size in
            var linePath = Path()
            var y = size.height / 3
            while y < size.height {
                linePath.move(to: CGPoint(x: 0, y: y))
                linePath.addLine(to: CGPoint(x: size.width, y: y))
                y += RuledMetrics.lineSpacing
            }
            context.stroke(linePath, with: .color(Color(RuledMetrics.lineColor)), lineWidth: RuledMetrics.lineWidth)

            var marginPath = Path()
            marginPath.move(to: CGPoint(x: RuledMetrics.marginX, y: 0))
            marginPath.addLine(to: CGPoint(x: RuledMetrics.marginX, y: size.height))
            context.stroke(marginPath, with: .color(Color(RuledMetrics.marginColor)), lineWidth: RuledMetrics.marginWidth)
        }
        .allowsHitTesting(false)
    }
}

final class OverlayHostView: UIView {}

struct OverlayHost: UIViewRepresentable {
    let view: OverlayHostView
    func makeUIView(context: Context) -> OverlayHostView { view }
    func updateUIView(_ uiView: OverlayHostView, context: Context) {}
}
