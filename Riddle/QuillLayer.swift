import UIKit

/// 隐形的笔：把句子合成为笔画并逐笔写在纸上。
///
/// 两条数据源路径：
/// - 字体骨架化（现有五款手迹）：整行光栅化→细化→追踪→抽稀→人味化，`writeViaFont`。
/// - SDT 轨迹（手泽）：逐字判断字库是否含该字，含则直接取轨迹点做人味化+曲线平滑；
///   字库外的字（标点/数字/生僻字/拉丁）单字回落到字体路径，`writeViaBank`。
///   两路共用同一套逐字光标（`GlyphLayout`），保证混排时标点与轨迹字同一基线、同一推进节奏。
@MainActor
final class QuillLayer {
    private let host: UIView
    private let pageBounds: CGRect
    private var cursorY: CGFloat
    private var written: [CAShapeLayer] = []
    private let rasterPx: CGFloat = 128           // 大字号光栅化保骨架质量
    private let lineHeightOnPage: CGFloat = 44    // 页面上的行高
    private let margin: CGFloat = 80
    private let inkColor: CGColor = Ink.quillColor.cgColor   // 回合开始时定色，换纸不影响写到一半的回信

    /// 轨迹字的固定视觉尺寸：贴近字体路径缩放到 lineHeightOnPage 后的字高观感。
    private let bankGlyphSize: CGFloat = 40
    private let bankCharSpacing: CGFloat = 6

    init(host: UIView, pageBounds: CGRect) {
        self.host = host
        self.pageBounds = pageBounds
        self.cursorY = pageBounds.height / 3
    }

    private func font(for text: String) -> UIFont {
        let hasCJK = text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        let name = hasCJK ? ReplyHandStore.shared.current.fontName : "DancingScript-Regular"
        return UIFont(name: name, size: rasterPx)!
    }

    /// 单字回落字体：CJK 用手迹自带字体，非 CJK（拉丁/数字）用手写体，与 `font(for:)` 的整行判断同一逻辑，
    /// 只是缩小到单字粒度，供轨迹路径里字库外的字符使用。
    private func fallbackFont(for char: Character, cjkFontName: String) -> UIFont {
        let isCJK = char.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        let name = isCJK ? cjkFontName : "DancingScript-Regular"
        return UIFont(name: name, size: rasterPx) ?? UIFont(name: cjkFontName, size: rasterPx) ?? UIFont.systemFont(ofSize: rasterPx)
    }

    func write(_ sentence: String, completion: @escaping () -> Void) {
        let hand = ReplyHandStore.shared.current
        if let bankStyle = hand.bankStyle, let bank = HandBankStore.shared.bank(for: bankStyle) {
            writeViaBank(sentence, bank: bank, fallbackHandFontName: hand.fontName, completion: completion)
        } else {
            writeViaFont(sentence, completion: completion)
        }
    }

    /// 现有字体骨架化路径：整行光栅化→细化→追踪→抽稀→人味化。字体款（现有五款）与手泽遇字库外整行
    /// （理论上不会整行都在库外，但结构上仍走得通）都走这里。逻辑与 Task 2 之前完全一致，未改动。
    private func writeViaFont(_ sentence: String, completion: @escaping () -> Void) {
        let f = font(for: sentence)
        let scaleDown = lineHeightOnPage / rasterPx * (rasterPx / f.lineHeight) // 归一到行高
        let maxRasterWidth = (pageBounds.width - margin * 2) / scaleDown
        let lines = Script.wrap(sentence, font: f, maxWidth: maxRasterWidth)

        var delay: CFTimeInterval = 0
        var rng = SystemRandomNumberGenerator()
        for line in lines {
            var mask = Script.rasterize(line, font: f)
            Script.thin(&mask)
            let simplified = Script.trace(mask).map { Script.simplify($0) }
            let strokes = Script.humanize(simplified, using: &rng)
            let lineY = cursorY
            cursorY += lineHeightOnPage

            for stroke in strokes {
                addAnimatedStroke(stroke, scale: scaleDown, position: CGPoint(x: margin, y: lineY),
                                   rng: &rng, delay: &delay)
            }
        }
        delay += 0.35                               // 句间 350ms
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { completion() }
    }

    /// SDT 轨迹路径：逐字判定数据源。字库有该字 → 取轨迹点（em-box [0,1]，人味化+曲线平滑）；
    /// 字库没有 → 该单字回落到字体路径（只光栅化这一个字符）。两者共用 GlyphLayout 算出的同一套光标位置，
    /// 保证一句里"轨迹字"和"回落字"（标点/数字/拉丁）落在同一行、同一基线、按同一节奏推进。
    private func writeViaBank(_ sentence: String, bank: HandBank, fallbackHandFontName: String,
                               completion: @escaping () -> Void) {
        let cellWidth = bankGlyphSize + bankCharSpacing
        let maxWidth = pageBounds.width - margin * 2
        var rng = SystemRandomNumberGenerator()

        let placements = GlyphLayout.layout(sentence, cellWidth: cellWidth, lineHeight: lineHeightOnPage,
                                             maxWidth: maxWidth, origin: CGPoint(x: margin, y: cursorY))

        var delay: CFTimeInterval = 0
        for placement in placements {
            // GlyphLayout.resolveTrajectoryStrokes already returns fully page-mapped (scaled +
            // translated) and humanized points — same resolution logic HandPickerView's
            // renderTrajectory uses, see its doc — so each stroke is animated with an identity
            // transform (scale: 1, position: .zero).
            let strokes = GlyphLayout.resolveTrajectoryStrokes(
                for: placement, bank: bank, trajectoryGlyphSize: bankGlyphSize,
                fallbackTargetHeight: lineHeightOnPage,
                fallbackFont: fallbackFont(for: placement.char, cjkFontName: fallbackHandFontName),
                rng: &rng)
            for stroke in strokes {
                addAnimatedStroke(stroke, scale: 1, position: .zero, rng: &rng, delay: &delay)
            }
        }

        if let last = placements.last {
            cursorY = last.topLeft.y + lineHeightOnPage
        }
        delay += 0.35                               // 句间 350ms
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { completion() }
    }

    /// 单笔画的图层构建 + strokeEnd 动画，两条渲染路径共用：`scale` 把该笔画自身坐标系（字体路径是光栅像素，
    /// 轨迹路径是 em-box [0,1]）换算到页面 pt；`position` 是该笔画所属字/行在页面上的锚点。
    private func addAnimatedStroke(_ stroke: [CGPoint], scale: CGFloat, position: CGPoint,
                                    rng: inout SystemRandomNumberGenerator, delay: inout CFTimeInterval) {
        let layer = CAShapeLayer()
        layer.path = Script.smoothPath(stroke)
        let randomAlpha = CGFloat.random(in: 0.85...1.0, using: &rng)
        layer.strokeColor = UIColor(cgColor: inkColor).withAlphaComponent(randomAlpha).cgColor
        layer.fillColor = nil
        layer.lineWidth = CGFloat.random(in: 1.8...2.6, using: &rng) / scale
        layer.lineCap = .round
        layer.lineJoin = .round
        // 缩放 + 平移到页面位置
        layer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        layer.position = position
        layer.strokeEnd = 0
        host.layer.addSublayer(layer)
        written.append(layer)

        let length = pathLength(stroke) * scale
        let duration = max(Double(length) / 900.0, 0.02)
        let anim = CABasicAnimation(keyPath: "strokeEnd")
        anim.fromValue = 0
        anim.toValue = 1
        anim.beginTime = CACurrentMediaTime() + delay
        anim.duration = duration
        anim.fillMode = .both
        anim.isRemovedOnCompletion = false
        layer.add(anim, forKey: "write")
        layer.strokeEnd = 1
        delay += duration + 0.04            // 笔画间 40ms
    }

    func fadeOutAll(completion: @escaping () -> Void) {
        guard !written.isEmpty else { completion(); return }
        let layers = written
        written = []
        let dur = 1.2
        for (i, layer) in layers.enumerated() {
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = 1; anim.toValue = 0
            anim.beginTime = CACurrentMediaTime() + 0.08 * Double(i % 40)
            anim.duration = dur
            anim.fillMode = .both
            anim.isRemovedOnCompletion = false
            layer.add(anim, forKey: "fade")
        }
        let groups = Double(min(layers.count, 40))
        let total = 0.08 * groups + dur
        DispatchQueue.main.asyncAfter(deadline: .now() + total) {
            layers.forEach { $0.removeFromSuperlayer() }
            self.cursorY = self.pageBounds.height / 3
            completion()
        }
    }

    private func pathLength(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { acc, pair in
            acc + hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)
        }
    }
}
