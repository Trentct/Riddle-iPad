import SwiftUI
import PencilKit

/// 纯函数：笔迹包围盒是否"圈住"了落款区域——用交叠面积占落款自身面积的比例判定（而不是占笔迹自身面积），
/// 要求较高的交叠比例，防止书写内容不小心扫过纸角边缘时被误判为返回手势。
enum SignaturePick {
    static let overlapThreshold: CGFloat = 0.6

    static func isCircled(strokeBounds: CGRect, signatureFrame: CGRect) -> Bool {
        guard signatureFrame.width > 0, signatureFrame.height > 0 else { return false }
        let overlap = strokeBounds.intersection(signatureFrame)
        guard !overlap.isNull else { return false }
        let overlapArea = overlap.width * overlap.height
        let signatureArea = signatureFrame.width * signatureFrame.height
        return overlapArea / signatureArea >= overlapThreshold
    }
}

struct DiaryView: View {
    /// 圈住纸角落款、触发返回圈选页（合上本子）。
    let onReturnToPicker: () -> Void

    @State private var canvasView = PKCanvasView()
    @State private var overlayHost = OverlayHostView()
    @State private var engine: TurnEngine?
    @ObservedObject private var paperStore = PaperStyleStore.shared
    @ObservedObject private var handStore = ReplyHandStore.shared
    @ObservedObject private var onboardingStore = OnboardingStore.shared
    @StateObject private var handCache = HandSampleCache.shared
    /// 落款的命中区域（已含圈选容错），供 `checkSignatureCircle` 判定；随容器尺寸/角色/缓存就绪重算。
    @State private var signatureFrame: CGRect = .zero
    @State private var signatureCheckTask: Task<Void, Never>?
    /// 首次引导墨迹：延时展示、写完停留后淡出；用户落笔时随时被抢占（见 `cancelOnboardingGuideIfNeeded`）。
    @State private var onboardingTask: Task<Void, Never>?
    @State private var onboardingQuill: QuillLayer?

    private let signatureMargin: CGFloat = 40
    private let signatureHeight: CGFloat = 36
    private let signatureHitTolerance: CGFloat = 16

    var body: some View {
        let style = paperStore.current
        GeometryReader { geo in
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
                    if !drawing.strokes.isEmpty { cancelOnboardingGuideIfNeeded() }
                    engine?.drawingChanged(drawing)
                    scheduleSignatureCheck()
                }
                .ignoresSafeArea()
                OverlayHost(view: overlayHost).ignoresSafeArea().allowsHitTesting(false)

                signatureView(containerSize: geo.size)
            }
            .onAppear {
                let firstAppear = engine == nil
                if engine == nil {
                    engine = TurnEngine(canvasView: canvasView, overlayHost: overlayHost)
                }
                // 正常流程里 HandPickerView 总是先出现过、早已 warm() 好缓存；这里再调一次是防御性的——
                // warm() 内部按 started 去重，已热过时直接返回，不会重复渲染。
                handCache.warm()
                signatureFrame = computeSignatureFrame(containerSize: geo.size)
                if firstAppear && !onboardingStore.hasSeenOnboarding {
                    startOnboardingGuide(pageBounds: CGRect(origin: .zero, size: geo.size))
                }
            }
            .onChange(of: geo.size) { _, newSize in
                signatureFrame = computeSignatureFrame(containerSize: newSize)
            }
            .onChange(of: handCache.images.count) { _, _ in
                // 落款图片可能在首次 onAppear 时还没缓存好，缓存陆续写入后需要重算命中框。
                signatureFrame = computeSignatureFrame(containerSize: geo.size)
            }
        }
        .ignoresSafeArea()
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
    }

    /// 纸面右下角常驻的当前角色落款：用其自己的字迹渲染（复用 HandSampleCache，跟圈选页三行同一份缓存），
    /// 极淡透明度，像信末署名；不接受手势（返回判定走 `signatureFrame` 纯几何计算，不靠这层视图命中）。
    @ViewBuilder
    private func signatureView(containerSize: CGSize) -> some View {
        if let image = handCache.images[handStore.current.id] {
            let maxWidth = containerSize.width * 0.4
            let fitted = HandPickerView.fittedSize(natural: image.size, maxWidth: maxWidth, maxHeight: signatureHeight)
            Image(uiImage: image)
                .resizable()
                .frame(width: fitted.width, height: fitted.height)
                .opacity(0.25)
                .position(x: containerSize.width - signatureMargin - fitted.width / 2,
                          y: containerSize.height - signatureMargin - fitted.height / 2)
                .allowsHitTesting(false)
        }
    }

    /// 落款「实际显示出的」矩形（与 `signatureView` 同一套 `fittedSize` + 定位数学，避免命中框与视觉错位），
    /// 再向四周放宽 `signatureHitTolerance` 作为圈选容错。缓存里还没有该角色图片时返回 .zero（不可能被圈中）。
    private func computeSignatureFrame(containerSize: CGSize) -> CGRect {
        guard let image = handCache.images[handStore.current.id] else { return .zero }
        let maxWidth = containerSize.width * 0.4
        let fitted = HandPickerView.fittedSize(natural: image.size, maxWidth: maxWidth, maxHeight: signatureHeight)
        let rect = CGRect(x: containerSize.width - signatureMargin - fitted.width,
                           y: containerSize.height - signatureMargin - fitted.height,
                           width: fitted.width, height: fitted.height)
        return rect.insetBy(dx: -signatureHitTolerance, dy: -signatureHitTolerance)
    }

    /// 笔迹变化去抖 0.35s 后判定：最近一笔的包围盒是否圈住了落款。命中时把那一笔从画布上摘掉——
    /// 它不算书写内容，不会被 TurnEngine 提交给 Oracle——再触发返回圈选页。
    /// 若此刻回信在途，TurnEngine 早在这一笔画下的瞬间（`engine?.drawingChanged` 已被调用过）就已经走过
    /// 既有的 turnID 抢占逻辑作废旧回合，这里不需要重复处理。
    private func scheduleSignatureCheck() {
        signatureCheckTask?.cancel()
        signatureCheckTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.35))
            guard !Task.isCancelled else { return }
            checkSignatureCircle()
        }
    }

    private func checkSignatureCircle() {
        guard let lastStroke = canvasView.drawing.strokes.last else { return }
        guard SignaturePick.isCircled(strokeBounds: lastStroke.renderBounds, signatureFrame: signatureFrame) else { return }

        var strokes = canvasView.drawing.strokes
        strokes.removeLast()
        canvasView.drawing = PKDrawing(strokes: strokes)   // 触发 engine 再收到一次变化：idle 计时器复位，不会把这笔提交
        onReturnToPicker()
    }

    /// 首次引导：停顿 0.8s 后以当前角色笔迹写下引导句（overlay 层，永不进画布/永不发给 Oracle），
    /// 停留 2.5s 供阅读，再淡出——淡出完成才标记"已见过"。全程任一步都可能被 `cancelOnboardingGuideIfNeeded`
    /// 抢占（用户落笔优先），每次 await 之后都检查 `Task.isCancelled` 及时让位。
    private func startOnboardingGuide(pageBounds: CGRect) {
        onboardingTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            guard canvasView.drawing.strokes.isEmpty else { return }   // 停顿期间用户已经落笔，让位

            let quill = QuillLayer(host: overlayHost, pageBounds: pageBounds)
            onboardingQuill = quill
            let line = OnboardingGuide.line(for: handStore.current)

            await withCheckedContinuation { cont in
                quill.write(line) { cont.resume() }
            }
            guard !Task.isCancelled else { return }

            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }

            await withCheckedContinuation { cont in
                quill.fadeOutAll { cont.resume() }
            }
            onboardingQuill = nil
            onboardingStore.markSeen()
        }
    }

    /// 用户开始写字：立即让引导墨迹让位。若还在停顿期（笔迹尚未画出）静默取消；
    /// 若已经在纸上（哪怕只写了一半），直接淡出——复用与 TurnEngine 落笔抢占同样的观感。
    /// 无论哪种情况，引导都算"已经出现过"，标记已见过，不会再次触发。
    private func cancelOnboardingGuideIfNeeded() {
        guard onboardingTask != nil else { return }
        onboardingTask?.cancel()
        onboardingTask = nil
        if let quill = onboardingQuill {
            onboardingQuill = nil
            quill.fadeOutAll {}
        }
        onboardingStore.markSeen()
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
