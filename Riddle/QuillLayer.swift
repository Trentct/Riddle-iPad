import UIKit

/// 隐形的笔：把句子合成为笔画并逐笔写在纸上。
final class QuillLayer {
    private let host: UIView
    private let pageBounds: CGRect
    private var cursorY: CGFloat
    private var written: [CAShapeLayer] = []
    private let rasterPx: CGFloat = 128           // 大字号光栅化保骨架质量
    private let lineHeightOnPage: CGFloat = 44    // 页面上的行高
    private let margin: CGFloat = 80
    private let inkColor: CGColor = Ink.quillColor.cgColor   // 回合开始时定色，换纸不影响写到一半的回信

    init(host: UIView, pageBounds: CGRect) {
        self.host = host
        self.pageBounds = pageBounds
        self.cursorY = pageBounds.height / 3
    }

    private func font(for text: String) -> UIFont {
        let hasCJK = text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        let name = hasCJK ? "LXGWWenKai-Regular" : "DancingScript-Regular"
        return UIFont(name: name, size: rasterPx)!
    }

    func write(_ sentence: String, completion: @escaping () -> Void) {
        let f = font(for: sentence)
        let scaleDown = lineHeightOnPage / rasterPx * (rasterPx / f.lineHeight) // 归一到行高
        let maxRasterWidth = (pageBounds.width - margin * 2) / scaleDown
        let lines = Script.wrap(sentence, font: f, maxWidth: maxRasterWidth)

        var delay: CFTimeInterval = 0
        for line in lines {
            var mask = Script.rasterize(line, font: f)
            Script.thin(&mask)
            var rng = SystemRandomNumberGenerator()
            let strokes = Script.humanize(Script.trace(mask), using: &rng)
            let lineY = cursorY
            cursorY += lineHeightOnPage

            for stroke in strokes {
                let path = UIBezierPath()
                path.move(to: stroke[0])
                for p in stroke.dropFirst() { path.addLine(to: p) }

                let layer = CAShapeLayer()
                layer.path = path.cgPath
                let randomAlpha = CGFloat.random(in: 0.85...1.0, using: &rng)
                layer.strokeColor = UIColor(cgColor: inkColor).withAlphaComponent(randomAlpha).cgColor
                layer.fillColor = nil
                layer.lineWidth = CGFloat.random(in: 1.8...2.6, using: &rng) / scaleDown
                layer.lineCap = .round
                layer.lineJoin = .round
                // 缩放 + 平移到页面位置
                layer.setAffineTransform(CGAffineTransform(scaleX: scaleDown, y: scaleDown))
                layer.position = CGPoint(x: margin, y: lineY)
                layer.strokeEnd = 0
                host.layer.addSublayer(layer)
                written.append(layer)

                let length = pathLength(stroke) * scaleDown
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
        }
        delay += 0.35                               // 句间 350ms
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { completion() }
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
