import UIKit
import PencilKit

enum FadeLayer {
    /// 把 drawing 的每一笔渲染成独立 layer，按书写顺序逐笔淡出，像墨水被纸吸走。
    static func drink(_ drawing: PKDrawing, in host: UIView, bounds: CGRect,
                      slowFactor: Double = 1.0, completion: @escaping () -> Void) {
        let strokes = drawing.strokes
        guard !strokes.isEmpty else { completion(); return }

        let scale = UIScreen.main.scale
        let stagger = 0.08 * slowFactor      // 笔间错开
        let fadeDur = 1.2 * slowFactor       // 单笔淡出时长
        let total = stagger * Double(strokes.count - 1) + fadeDur
        var layers: [CALayer] = []

        for (i, stroke) in strokes.enumerated() {
            let single = PKDrawing(strokes: [stroke])
            let image = single.image(from: bounds, scale: scale)
            let layer = CALayer()
            layer.frame = bounds
            layer.contents = image.cgImage
            layer.contentsScale = scale
            host.layer.addSublayer(layer)
            layers.append(layer)

            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = 1.0
            anim.toValue = 0.0
            anim.beginTime = CACurrentMediaTime() + stagger * Double(i)
            anim.duration = fadeDur
            anim.timingFunction = CAMediaTimingFunction(name: .easeIn)
            anim.fillMode = .both
            anim.isRemovedOnCompletion = false
            layer.add(anim, forKey: "fade")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + total + 0.05) {
            layers.forEach { $0.removeFromSuperlayer() }
            completion()
        }
    }
}
