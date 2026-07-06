import UIKit
import CoreImage

/// 程序生成的纸张噪点纹理（无需图片资产），启动时生成一次 256pt 可平铺 tile。
enum PaperTexture {
    static let tile: UIImage = {
        let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!
        let rect = CGRect(x: 0, y: 0, width: 256, height: 256)
        let mono = noise
            .cropped(to: rect)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0,
                kCIInputContrastKey: 0.6,
                kCIInputBrightnessKey: 0,
            ])
        let ctx = CIContext(options: nil)
        guard let cg = ctx.createCGImage(mono, from: rect) else { return UIImage() }
        return UIImage(cgImage: cg)
    }()

    /// 宣纸用：噪点横向拉伸 4×后重新取样，得到横向纤维感（叠加在 `tile` 之上，低透明度）。
    static let fiberTile: UIImage = {
        let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!
        let stretched = noise.transformed(by: CGAffineTransform(scaleX: 4, y: 1))
        let rect = CGRect(x: 0, y: 0, width: 256, height: 256)
        let mono = stretched
            .cropped(to: rect)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0,
                kCIInputContrastKey: 0.6,
                kCIInputBrightnessKey: 0,
            ])
        let ctx = CIContext(options: nil)
        guard let cg = ctx.createCGImage(mono, from: rect) else { return UIImage() }
        return UIImage(cgImage: cg)
    }()
}
