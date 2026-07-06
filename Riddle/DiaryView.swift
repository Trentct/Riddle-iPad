import SwiftUI
import PencilKit

struct DiaryView: View {
    private let canvasView = PKCanvasView()

    var body: some View {
        ZStack {
            Color(Ink.paperColor).ignoresSafeArea()
            // 轻微暗角：径向渐变叠加
            RadialGradient(colors: [.clear, .black.opacity(0.08)],
                           center: .center, startRadius: 200, endRadius: 900)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            InkCanvas(canvasView: canvasView) { drawing in
                // Task 9 在此接 TurnEngine
                _ = drawing
            }
            .ignoresSafeArea()
        }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
    }
}
