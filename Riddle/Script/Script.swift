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

    /// 把骨架追踪成折线笔画，按最小 x 排序使动画像人手从左往右写。
    static func trace(_ mask: InkMask) -> [[CGPoint]] {
        let w = mask.width, h = mask.height
        func at(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < w && y < h && mask.pixels[y * w + x]
        }
        func neighbors(_ x: Int, _ y: Int) -> [(Int, Int)] {
            var out: [(Int, Int)] = []
            for dy in -1...1 {
                for dx in -1...1 where dx != 0 || dy != 0 {
                    if at(x + dx, y + dy) { out.append((x + dx, y + dy)) }
                }
            }
            return out
        }
        var visited = [Bool](repeating: false, count: w * h)
        // 端点（度=1）优先作为起点，然后是剩余点（环）。
        var starts: [(Int, Int)] = []
        for y in 0..<h { for x in 0..<w where at(x, y) && neighbors(x, y).count == 1 { starts.append((x, y)) } }
        for y in 0..<h { for x in 0..<w where at(x, y) { starts.append((x, y)) } }
        var strokes: [[CGPoint]] = []
        for (sx, sy) in starts {
            if visited[sy * w + sx] { continue }
            var path = [CGPoint(x: CGFloat(sx), y: CGFloat(sy))]
            visited[sy * w + sx] = true
            var (cx, cy) = (sx, sy)
            while let next = neighbors(cx, cy).first(where: { !visited[$0.1 * w + $0.0] }) {
                visited[next.1 * w + next.0] = true
                path.append(CGPoint(x: CGFloat(next.0), y: CGFloat(next.1)))
                (cx, cy) = next
            }
            if path.count >= 3 { strokes.append(path) }
        }
        strokes.sort { a, b in a.map(\.x).min()! < b.map(\.x).min()! }
        return strokes
    }
}
