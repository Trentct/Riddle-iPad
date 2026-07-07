import SwiftUI
import PencilKit

/// 纯函数：笔迹包围盒 vs 各行 frame，返回交叠面积最大且 >0 的行号；无正交叠返回 nil。
enum CirclePick {
    static func pickRow(strokeBounds: CGRect, rowFrames: [CGRect]) -> Int? {
        var bestIndex: Int?
        var bestArea: CGFloat = 0
        for (index, frame) in rowFrames.enumerated() {
            let overlap = strokeBounds.intersection(frame)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > bestArea {
                bestArea = area
                bestIndex = index
            }
        }
        return bestArea > 0 ? bestIndex : nil
    }
}

/// 把一款手迹的样字句子经 Script 管线（rasterize→thin→trace→humanize）渲染成静态 UIImage。
/// 计算较慢（~0.2-0.3s/款），务必只在后台调用一次并缓存。
enum HandSampleRenderer {
    static let sentence = "哈利波特，真是个有趣的名字"
    static let rowHeight: CGFloat = 64
    private static let rasterFontSize: CGFloat = 96
    private static let rasterLineWidth: CGFloat = 2.4

    static func render(_ hand: ReplyHand, inkColor: CGColor) -> UIImage {
        guard let font = UIFont(name: hand.fontName, size: rasterFontSize) else { return UIImage() }
        var mask = Script.rasterize(sentence, font: font)
        Script.thin(&mask)
        var rng = SystemRandomNumberGenerator()
        let strokes = Script.humanize(Script.trace(mask), using: &rng)
        let points = strokes.flatMap { $0 }
        guard !points.isEmpty else { return UIImage() }

        let minX = points.map(\.x).min()!, maxX = points.map(\.x).max()!
        let minY = points.map(\.y).min()!, maxY = points.map(\.y).max()!
        let pad: CGFloat = 6
        let rasterSize = CGSize(width: maxX - minX + pad * 2, height: maxY - minY + pad * 2)

        let rasterImage = UIGraphicsImageRenderer(size: rasterSize).image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(x: pad - minX, y: pad - minY)
            cg.setStrokeColor(inkColor)
            cg.setLineWidth(rasterLineWidth)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for stroke in strokes {
                guard let first = stroke.first else { continue }
                cg.beginPath()
                cg.move(to: first)
                for p in stroke.dropFirst() { cg.addLine(to: p) }
                cg.strokePath()
            }
        }

        // 缩放到目标行高（线宽随之等比缩小，与骨架保持统一粗细感）。
        let scale = rowHeight / rasterSize.height
        let finalSize = CGSize(width: rasterSize.width * scale, height: rowHeight)
        return UIGraphicsImageRenderer(size: finalSize).image { _ in
            rasterImage.draw(in: CGRect(origin: .zero, size: finalSize))
        }
    }
}

/// 四款样字图片的缓存：首次 warm() 时在后台线程一次性渲染，避免卡顿启动首帧。
@MainActor
final class HandSampleCache: ObservableObject {
    static let shared = HandSampleCache()
    @Published private(set) var images: [String: UIImage] = [:]
    private var started = false

    func warm() {
        guard !started else { return }
        started = true
        let inkColor = Ink.quillColor.cgColor
        Task.detached(priority: .userInitiated) {
            let result = Dictionary(uniqueKeysWithValues: ReplyHands.all.map { hand in
                (hand.id, HandSampleRenderer.render(hand, inkColor: inkColor))
            })
            await MainActor.run { self.images = result }
        }
    }
}

/// 圈选页顶层的 PencilKit 画布：双端 `.anyInput`（护栏——手指等价），去抖 0.6s 后命中判定。
private struct PickCanvas: UIViewRepresentable {
    let canvasView: PKCanvasView
    let rowFrames: () -> [CGRect]
    let onPick: (Int) -> Void
    let onMiss: () -> Void

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.tool = PKInkingTool(.pen, color: Ink.userColor, width: 3)
        canvasView.drawingPolicy = .anyInput   // 双端一致：护栏——手指等价，圈选无需笔
        canvasView.isScrollEnabled = false
        canvasView.delegate = context.coordinator
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(canvasView: canvasView, rowFrames: rowFrames, onPick: onPick, onMiss: onMiss)
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private weak var canvasView: PKCanvasView?
        private let rowFrames: () -> [CGRect]
        private let onPick: (Int) -> Void
        private let onMiss: () -> Void
        private var debounceTask: Task<Void, Never>?

        init(canvasView: PKCanvasView, rowFrames: @escaping () -> [CGRect],
             onPick: @escaping (Int) -> Void, onMiss: @escaping () -> Void) {
            self.canvasView = canvasView
            self.rowFrames = rowFrames
            self.onPick = onPick
            self.onMiss = onMiss
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            debounceTask?.cancel()
            debounceTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(0.6))
                guard !Task.isCancelled, let self, let canvasView = self.canvasView else { return }
                let drawing = canvasView.drawing
                guard !drawing.strokes.isEmpty else { return }
                if let index = CirclePick.pickRow(strokeBounds: drawing.bounds, rowFrames: self.rowFrames()) {
                    self.onPick(index)
                } else {
                    self.onMiss()
                }
            }
        }
    }
}

/// 启动即进入的圈选页：竖排四行样字，圈起其一即全局切换回信笔迹。DiaryView 本身不受影响。
struct HandPickerView: View {
    let onPicked: (ReplyHand) -> Void

    @State private var canvasView = PKCanvasView()
    @State private var fadeHost = OverlayHostView()
    @StateObject private var cache = HandSampleCache.shared
    @State private var rowFrames: [CGRect] = []
    @State private var flashIndex: Int?
    @State private var contentOpacity: Double = 1
    @State private var isPicked = false

    private let rowSpacing: CGFloat = 40
    private let guideBlockHeight: CGFloat = 96

    var body: some View {
        GeometryReader { geo in
            let frames = computeRowFrames(containerSize: geo.size)
            ZStack {
                Color(Ink.paperColor).ignoresSafeArea()
                Image(uiImage: PaperTexture.tile)
                    .resizable(resizingMode: .tile)
                    .opacity(0.05)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                RadialGradient(colors: [.clear, .black.opacity(0.1)],
                               center: .center, startRadius: 200, endRadius: 900)
                    .ignoresSafeArea().allowsHitTesting(false)

                Text("圈选一种字迹")
                    .font(.custom(ReplyHands.xiaxing.fontName, size: 30))
                    .foregroundStyle(Color(Ink.quillColor))
                    .position(x: geo.size.width / 2, y: layoutTopY(containerSize: geo.size) + guideBlockHeight / 2)

                ForEach(Array(ReplyHands.all.enumerated()), id: \.offset) { index, hand in
                    rowImage(hand: hand, index: index)
                        .position(x: geo.size.width / 2, y: frames[index].midY)
                }

                PickCanvas(canvasView: canvasView, rowFrames: { rowFrames },
                           onPick: handlePick, onMiss: handleMiss)
                    .ignoresSafeArea()
                OverlayHost(view: fadeHost).ignoresSafeArea().allowsHitTesting(false)
            }
            .opacity(contentOpacity)
            .onAppear {
                cache.warm()
                rowFrames = frames
            }
            .onChange(of: geo.size) { _, newSize in
                rowFrames = computeRowFrames(containerSize: newSize)
            }
        }
        .ignoresSafeArea()
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
    }

    @ViewBuilder
    private func rowImage(hand: ReplyHand, index: Int) -> some View {
        if let image = cache.images[hand.id] {
            Image(uiImage: image)
                .scaleEffect(flashIndex == index ? 1.03 : 1.0)
                .brightness(flashIndex == index ? -0.4 : 0)
                .animation(.easeInOut(duration: 0.4), value: flashIndex)
        } else {
            Color.clear.frame(width: 1, height: HandSampleRenderer.rowHeight)
        }
    }

    /// 整个圈选区块（引导语 + 四行样字）在容器中垂直居中后的顶部 y；引导语与各行 frame 共用同一计算，避免错位。
    private func layoutTopY(containerSize: CGSize) -> CGFloat {
        let count = CGFloat(ReplyHands.all.count)
        let totalHeight = guideBlockHeight + count * HandSampleRenderer.rowHeight + (count - 1) * rowSpacing
        return max(40, (containerSize.height - totalHeight) / 2)
    }

    private func computeRowFrames(containerSize: CGSize) -> [CGRect] {
        let rowHeight = HandSampleRenderer.rowHeight
        let topY = layoutTopY(containerSize: containerSize)
        return ReplyHands.all.indices.map { i in
            let y = topY + guideBlockHeight + CGFloat(i) * (rowHeight + rowSpacing)
            return CGRect(x: 0, y: y, width: containerSize.width, height: rowHeight)
        }
    }

    private func handlePick(_ index: Int) {
        guard !isPicked, ReplyHands.all.indices.contains(index) else { return }
        isPicked = true
        let hand = ReplyHands.all[index]
        flashIndex = index
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.4))
            withAnimation(.easeInOut(duration: 0.35)) { contentOpacity = 0 }
            try? await Task.sleep(for: .seconds(0.35))
            onPicked(hand)
        }
    }

    private func handleMiss() {
        guard !isPicked else { return }
        let drawing = canvasView.drawing
        guard !drawing.strokes.isEmpty else { return }
        let bounds = canvasView.bounds
        canvasView.drawing = PKDrawing()
        FadeLayer.drink(drawing, in: fadeHost, bounds: bounds) {}
    }
}
