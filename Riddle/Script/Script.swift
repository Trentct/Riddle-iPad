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
}
