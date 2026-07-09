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

/// 把一款手迹渲染任意文本（圈选页用角色名，DiaryView 落款也复用同一套渲染）经 Script 管线
/// （rasterize→thin→trace→humanize）渲染成静态 UIImage。
/// 计算较慢（~0.2-0.3s/款），务必只在后台调用一次并缓存。
enum HandSampleRenderer {
    static let rowHeight: CGFloat = 64
    private static let rasterFontSize: CGFloat = 96
    private static let rasterLineWidth: CGFloat = 2.4

    static func render(_ hand: ReplyHand, text: String, inkColor: CGColor) -> UIImage {
        guard let font = UIFont(name: hand.fontName, size: rasterFontSize) else { return UIImage() }
        var mask = Script.rasterize(text, font: font)
        Script.thin(&mask)
        var rng = SystemRandomNumberGenerator()
        let simplified = Script.trace(mask).map { Script.simplify($0) }
        let strokes = Script.humanize(simplified, using: &rng)
        return rasterStrokes(strokes, inkColor: inkColor)
    }

    /// 手泽（SDT 轨迹字库驱动）的样字渲染：与字体款共用 `GlyphLayout` 的逐字光标（QuillLayer 的
    /// `writeViaBank` 也用同一套排版数学），确保圈选页第一行（归野）展示的就是真实轨迹笔迹，而不是字体骨架化。
    /// 字库里没有的字符单字回落到字体路径。
    static func renderTrajectory(bank: HandBank, text: String, fallbackFontName: String, inkColor: CGColor) -> UIImage {
        let glyphSize = rasterFontSize             // 与字体款用同一光栅尺度，人味化幅度才可比
        let charSpacing = glyphSize * 0.15
        let cellWidth = glyphSize + charSpacing
        var rng = SystemRandomNumberGenerator()

        let placements = GlyphLayout.layout(text, cellWidth: cellWidth, lineHeight: glyphSize * 1.3,
                                             maxWidth: .greatestFiniteMagnitude, origin: .zero)
        // GlyphLayout.resolveTrajectoryStrokes holds the resolution logic shared with
        // QuillLayer.writeViaBank (bank hit → page-mapped + humanized trajectory; miss →
        // single-char font fallback) — see its doc.
        var allStrokes: [[CGPoint]] = []
        for placement in placements {
            let strokes = GlyphLayout.resolveTrajectoryStrokes(
                for: placement, bank: bank, trajectoryGlyphSize: glyphSize,
                fallbackTargetHeight: glyphSize,
                fallbackFont: UIFont(name: fallbackFontName, size: rasterFontSize),
                rng: &rng)
            allStrokes.append(contentsOf: strokes)
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

/// 按角色选对渲染路径（手泽走轨迹字库、其余走字体骨架化），`HandSampleCache`（圈选页/落款，墨色）与
/// `BookNameCache`（书封，烫金色，见 BookCover.swift）共用同一份分支逻辑——两处唯一的差异只是 inkColor，
/// 渲染算法本身（HandSampleRenderer）不重复实现。`bank` 由调用方在 MainActor 上下文里先取出再传入
/// （HandBankStore.bank(for:) 是 @MainActor 同步调用，不能在 Task.detached 内部调用）。
enum HandNameRenderer {
    static func render(_ hand: ReplyHand, bank: HandBank?, inkColor: CGColor) -> UIImage {
        if let bank {
            return HandSampleRenderer.renderTrajectory(bank: bank, text: hand.name,
                                                        fallbackFontName: hand.fontName, inkColor: inkColor)
        }
        return HandSampleRenderer.render(hand, text: hand.name, inkColor: inkColor)
    }
}

/// 三款角色名样字图片的缓存：首次 warm() 时在后台线程一次性渲染，避免卡顿启动首帧。
/// 圈选页三行、DiaryView 纸角落款都共用同一份缓存（同一角色的名字只需渲染一次）。
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
                (hand.id, HandNameRenderer.render(hand, bank: banks[hand.id], inkColor: inkColor))
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

/// 启动即进入的圈选页：竖排三行，每行是该角色的名字（各自字迹渲染），圈起其一即全局切换回信角色。DiaryView 本身不受影响。
struct HandPickerView: View {
    let onPicked: (ReplyHand) -> Void

    @State private var canvasView = PKCanvasView()
    @State private var fadeHost = OverlayHostView()
    @StateObject private var cache = HandSampleCache.shared
    @State private var rowFrames: [CGRect] = []
    @State private var flashIndex: Int?
    @State private var isPicked = false
    @State private var showAbout = false

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
                PaperMetalView(style: PaperStyleStore.shared.current)

                Text("以笔圈定一种字迹，我便用它回信")
                    .font(.custom(ReplyHands.shouze.fontName, size: 30))
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

                settingsMark(containerSize: geo.size)
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
        .sheet(isPresented: $showAbout) {
            AboutView(onDismiss: { showAbout = false })
        }
    }

    /// 圈选页是全屏 PencilKit 画布（`PickCanvas`），这本子里唯一"非纸面"的入口只能靠一个不入戏的
    /// 小机关触达：右下角一枚极淡的墨点，轻点（非圈选）即可打开关于/设置页——因为这是元层面
    /// （致谢/隐私/音效/恢复购买），不是日记本身，所以允许用轻点代替圈选手势。
    /// 44×44 命中区域保证可访问性，视觉上只露出一个 10pt、8% 透明度的墨点，不抢纸面的注意力。
    private func settingsMark(containerSize: CGSize) -> some View {
        Button {
            showAbout = true
        } label: {
            Circle()
                .fill(Color(Ink.quillColor))
                .frame(width: 10, height: 10)
                .opacity(0.08)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("关于")
        .position(x: containerSize.width - 32, y: containerSize.height - 32)
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

    /// 整个圈选区块（引导语 + 三行角色名）在容器中垂直居中后的顶部 y；引导语与各行 frame 共用同一计算，避免错位。
    private func layoutTopY(containerSize: CGSize) -> CGFloat {
        let count = CGFloat(ReplyHands.all.count)
        let totalHeight = guideBlockHeight + count * HandSampleRenderer.rowHeight + (count - 1) * rowSpacing
        return max(40, (containerSize.height - totalHeight) / 2)
    }

    /// 命中框 = 每行「实际显示出的」角色名矩形（居中于该行中心，尺寸取自与 `rowImage` 同一套 `fittedSize` 缩放），
    /// 再向四周放宽 30pt 作为圈选容错（≥28pt 要求），而不是整条容器宽度——避免空白页边距也能被圈中。
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
            return rect.insetBy(dx: -30, dy: -30)
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
