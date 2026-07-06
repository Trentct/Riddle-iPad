// 手写合成管线：rasterize → thin → trace → wrap
// 算法移植自 MaximeRivest/Riddle (riddle/src/script.rs, MIT License)
// https://github.com/MaximeRivest/Riddle
import UIKit

enum Script {
    /// 把一行文本按 font 光栅化为布尔掩码（白字黑底，>50% 覆盖算墨点）。
    static func rasterize(_ text: String, font: UIFont) -> InkMask {
        let attr = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: UIColor.white,
        ])
        let size = attr.size()
        let w = max(Int(ceil(size.width)) + 4, 1)
        let h = max(Int(ceil(size.height)) + 4, 1)
        var gray = [UInt8](repeating: 0, count: w * h)
        gray.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(
                data: buf.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            UIGraphicsPushContext(ctx)
            ctx.translateBy(x: 0, y: CGFloat(h))
            ctx.scaleBy(x: 1, y: -1)
            attr.draw(at: CGPoint(x: 2, y: 2))
            UIGraphicsPopContext()
        }
        return InkMask(width: w, height: h, pixels: gray.map { $0 > 127 })
    }

    /// Zhang-Suen 细化：把掩码削成 1px 宽骨架。
    static func thin(_ mask: inout InkMask) {
        let w = mask.width, h = mask.height
        guard w >= 3 && h >= 3 else { return }
        while true {
            var changed = false
            for phase in 0..<2 {
                var toClear: [Int] = []
                for y in 1..<(h - 1) {
                    for x in 1..<(w - 1) {
                        guard mask.pixels[y * w + x] else { continue }
                        let p: [Bool] = [
                            mask.pixels[(y - 1) * w + x],       // p2 N
                            mask.pixels[(y - 1) * w + x + 1],   // p3 NE
                            mask.pixels[y * w + x + 1],         // p4 E
                            mask.pixels[(y + 1) * w + x + 1],   // p5 SE
                            mask.pixels[(y + 1) * w + x],       // p6 S
                            mask.pixels[(y + 1) * w + x - 1],   // p7 SW
                            mask.pixels[y * w + x - 1],         // p8 W
                            mask.pixels[(y - 1) * w + x - 1],   // p9 NW
                        ]
                        let b = p.filter { $0 }.count
                        guard (2...6).contains(b) else { continue }
                        var a = 0
                        for i in 0..<8 where !p[i] && p[(i + 1) % 8] { a += 1 }
                        guard a == 1 else { continue }
                        let c1: Bool, c2: Bool
                        if phase == 0 {
                            c1 = !(p[0] && p[2] && p[4]); c2 = !(p[2] && p[4] && p[6])
                        } else {
                            c1 = !(p[0] && p[2] && p[6]); c2 = !(p[0] && p[4] && p[6])
                        }
                        if c1 && c2 { toClear.append(y * w + x) }
                    }
                }
                if !toClear.isEmpty {
                    changed = true
                    for i in toClear { mask.pixels[i] = false }
                }
            }
            if !changed { break }
        }
    }
}
