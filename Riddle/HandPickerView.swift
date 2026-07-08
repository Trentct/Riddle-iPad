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
    static let sentence = "见字如面，落墨为凭。"
    static let rowHeight: CGFloat = 64
    private static let rasterFontSize: CGFloat = 96
    private static let rasterLineWidth: CGFloat = 2.4

    static func render(_ hand: ReplyHand, inkColor: CGColor) -> UIImage {
        guard let font = UIFont(name: hand.fontName, size: rasterFontSize) else { return UIImage() }
        var mask = Script.rasterize(sentence, font: font)
        Script.thin(&mask)
        var rng = SystemRandomNumberGenerator()
        let simplified = Script.trace(mask).map { Script.simplify($0) }
        let strokes = Script.humanize(simplified, using: &rng)
        return rasterStrokes(strokes, inkColor: inkColor)
    }

    /// 手泽（SDT 轨迹字库驱动）的样字渲染：与字体款共用 `GlyphLayout` 的逐字光标（QuillLayer 的
    /// `writeViaBank` 也用同一套排版数学），确保圈选页第六行展示的就是真实轨迹笔迹，而不是字体骨架化。
    /// 字库里没有的字符（这里主要是标点「，」「。」）单字回落到字体路径。
    static func renderTrajectory(bank: HandBank, fallbackFontName: String, inkColor: CGColor) -> UIImage {
        let glyphSize = rasterFontSize             // 与字体款用同一光栅尺度，人味化幅度才可比
        let charSpacing = glyphSize * 0.15
        let cellWidth = glyphSize + charSpacing
        var rng = SystemRandomNumberGenerator()

        let placements = GlyphLayout.layout(sentence, cellWidth: cellWidth, lineHeight: glyphSize * 1.3,
                                             maxWidth: .greatestFiniteMagnitude, origin: .zero)
        var allStrokes: [[CGPoint]] = []
        for placement in placements {
            let char = placement.char
            let variant = Int.random(in: 0..<2, using: &rng)
            if let trajectory = bank.strokes(for: char, variant: variant) ?? bank.strokes(for: char, variant: 0) {
                let mapped = trajectory.map { stroke in
                    stroke.map { p in
                        CGPoint(x: placement.topLeft.x + p.x * glyphSize, y: placement.topLeft.y + p.y * glyphSize)
                    }
                }
                allStrokes.append(contentsOf: Script.humanize(mapped, using: &rng))
            } else {
                guard let font = UIFont(name: fallbackFontName, size: rasterFontSize) else { continue }
                var mask = Script.rasterize(String(char), font: font)
                Script.thin(&mask)
                let simplified = Script.trace(mask).map { Script.simplify($0) }
                guard !simplified.isEmpty else { continue }
                let scale = glyphSize / font.lineHeight
                let mapped = simplified.map { stroke in
                    stroke.map { p in
                        CGPoint(x: placement.topLeft.x + p.x * scale, y: placement.topLeft.y + p.y * scale)
                    }
                }
                allStrokes.append(contentsOf: Script.humanize(mapped, using: &rng))
            }
        }
        return rasterStrokes(allStrokes, inkColor: inkColor)
    }

    /// 共享的笔画→图片光栅化：按笔画包围盒裁边，再等比缩放到目标行高。`render` 与 `renderTrajectory`
    /// 都以此收尾，保证两条数据源出来的样字图片视觉规格（线宽/边距/最终行高）一致。
    private static func rasterStrokes(_ strokes: [[CGPoint]], inkColor: CGColor) -> UIImage {
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
                guard !stroke.isEmpty else { continue }
                cg.beginPath()
                cg.addPath(Script.smoothPath(stroke))
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

/// 六款样字图片的缓存：首次 warm() 时在后台线程一次性渲染，避免卡顿启动首帧。
@MainActor
final class HandSampleCache: ObservableObject {
    static let shared = HandSampleCache()
    @Published private(set) var images: [String: UIImage] = [:]
    private var started = false

    func warm() {
        guard !started else { return }
        started = true
        let inkColor = Ink.quillColor.cgColor
        // bank(for:) 是 @MainActor 同步调用（HandSampleCache 本身也是 @MainActor），在派发到后台渲染前
        // 先在主线程把已加载（或按需加载）的 HandBank 取出来，交给下面的 detached task 做重活。
        let banks = Dictionary(uniqueKeysWithValues: ReplyHands.all.compactMap { hand -> (String, HandBank)? in
            guard let bankStyle = hand.bankStyle, let bank = HandBankStore.shared.bank(for: bankStyle) else { return nil }
            return (hand.id, bank)
        })
        Task.detached(priority: .userInitiated) {
            let result = Dictionary(uniqueKeysWithValues: ReplyHands.all.map { hand -> (String, UIImage) in
                if let bank = banks[hand.id] {
                    let image = HandSampleRenderer.renderTrajectory(bank: bank, fallbackFontName: hand.fontName,
                                                                     inkColor: inkColor)
                    return (hand.id, image)
                }
                return (hand.id, HandSampleRenderer.render(hand, inkColor: inkColor))
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
    @State private var isPicked = false

    private let rowSpacing: CGFloat = 40
    private let guideBlockHeight: CGFloat = 96
    private let hMargin: CGFloat = 60

    /// 纯函数：把 natural 尺寸等比缩放进 maxWidth×maxHeight 的框内，永不放大（scale 上限 1）。
    /// 供显示（`rowImage`）与命中框（`computeRowFrames`）共用同一套缩放数学，避免二者失配。
    static func fittedSize(natural: CGSize, maxWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
        let scale = min(maxHeight / natural.height, maxWidth / natural.width, 1)
        return CGSize(width: natural.width * scale, height: natural.height * scale)
    }

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

                Text("以笔圈定一种字迹，我便用它回信")
                    .font(.custom(ReplyHands.xiaxing.fontName, size: 30))
                    .foregroundStyle(Color(Ink.quillColor))
                    .position(x: geo.size.width / 2, y: layoutTopY(containerSize: geo.size) + guideBlockHeight / 2)

                ForEach(Array(ReplyHands.all.enumerated()), id: \.offset) { index, hand in
                    rowImage(hand: hand, index: index, containerSize: geo.size)
                        .position(x: geo.size.width / 2, y: frames[index].midY)
                }

                PickCanvas(canvasView: canvasView, rowFrames: { rowFrames },
                           onPick: handlePick, onMiss: handleMiss)
                    .ignoresSafeArea()
                OverlayHost(view: fadeHost).ignoresSafeArea().allowsHitTesting(false)
            }
            .onAppear {
                cache.warm()
                rowFrames = frames
            }
            .onChange(of: geo.size) { _, newSize in
                rowFrames = computeRowFrames(containerSize: newSize)
            }
            .onChange(of: cache.images.count) { _, _ in
                // 样字图片陆续从后台缓存写入后，命中框需要用真实图片尺寸重新计算（首次 onAppear 时可能还没缓存好）。
                rowFrames = computeRowFrames(containerSize: geo.size)
            }
        }
        .ignoresSafeArea()
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
    }

    @ViewBuilder
    private func rowImage(hand: ReplyHand, index: Int, containerSize: CGSize) -> some View {
        if let image = cache.images[hand.id] {
            let maxWidth = containerSize.width - 2 * hMargin
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: maxWidth, maxHeight: HandSampleRenderer.rowHeight)
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

    /// 命中框 = 每行「实际显示出的」样字矩形（居中于该行中心，尺寸取自与 `rowImage` 同一套 `fittedSize` 缩放），
    /// 再向四周放宽 24pt 作为圈选容错，而不是整条容器宽度——避免空白页边距也能被圈中。
    private func computeRowFrames(containerSize: CGSize) -> [CGRect] {
        let rowHeight = HandSampleRenderer.rowHeight
        let topY = layoutTopY(containerSize: containerSize)
        let maxWidth = containerSize.width - 2 * hMargin
        return ReplyHands.all.indices.map { i in
            let hand = ReplyHands.all[i]
            let centerY = topY + guideBlockHeight + CGFloat(i) * (rowHeight + rowSpacing) + rowHeight / 2
            let natural = cache.images[hand.id]?.size ?? CGSize(width: maxWidth, height: rowHeight)
            let fitted = Self.fittedSize(natural: natural, maxWidth: maxWidth, maxHeight: rowHeight)
            let rect = CGRect(x: containerSize.width / 2 - fitted.width / 2,
                               y: centerY - fitted.height / 2,
                               width: fitted.width, height: fitted.height)
            return rect.insetBy(dx: -24, dy: -24)
        }
    }

    private func handlePick(_ index: Int) {
        guard !isPicked, ReplyHands.all.indices.contains(index) else { return }
        isPicked = true
        let hand = ReplyHands.all[index]
        flashIndex = index
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.4))
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
