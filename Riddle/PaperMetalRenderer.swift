import Metal
import CoreImage
import UIKit

/// 着色器输入；字段顺序/类型需与 `PaperShader.metal` 里的 `PaperParams` 严格一致（Metal 按 C 对齐规则
/// 布局 constant 结构体，float4 对齐到 16 字节，Swift 侧用 SIMD4<Float> 保证同样的对齐/步幅）。
struct PaperShaderParams {
    var baseColor: SIMD4<Float>
    var grainIntensity: Float
    var grainScale: Float
    var fiberDirectionality: Float
    var fiberAngle: Float
    var warmth: Float
    var vignetteStrength: Float
    var aspect: Float
    var seed: Float
}

extension PaperStyle {
    /// 把产品语义的纸张参数（纸色/噪点强度/渐晕强度/纤维方向性/做旧）翻译成着色器输入。
    /// `aspect` 由渲染尺寸决定，不是样式自身属性，调用方传入。
    func shaderParams(aspect: Float) -> PaperShaderParams {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        paperColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        // 每种样式一个固定相位偏移，避免四张纸的噪声图案看起来像同一张贴图换了底色。
        let seed = Float(abs(id.hashValue % 1000)) * 0.37
        return PaperShaderParams(
            baseColor: SIMD4<Float>(Float(r), Float(g), Float(b), 1),
            grainIntensity: Float(noiseOpacity) * 1.9,
            grainScale: riceFiber ? 70 : (ruled ? 130 : 110),
            fiberDirectionality: Float(fiberDirectionality),
            fiberAngle: 0.4,
            warmth: Float(warmth),
            vignetteStrength: Float(vignetteOpacity),
            aspect: max(aspect, 0.0001),
            seed: seed)
    }
}

/// 离屏 Metal 渲染纸张材质：每种 style + 每个像素尺寸只渲染一次，结果缓存为 `UIImage` 供 SwiftUI 直接展示。
/// 静态背景不需要逐帧重绘——命中缓存零 GPU 开销，只有首次出现或尺寸变化（旋转/分屏）才触发一次新渲染，
/// 渲染永远按目标像素尺寸进行，天然分辨率无关，不会在不同 iPad 上模糊。
final class PaperMetalRenderer {
    static let shared = PaperMetalRenderer()

    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let pipelineState: MTLRenderPipelineState?
    private let ciContext: CIContext?
    private let cache = NSCache<NSString, UIImage>()

    init() {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let library = device.makeDefaultLibrary(),
            let vertexFn = library.makeFunction(name: "paper_vertex"),
            let fragmentFn = library.makeFunction(name: "paper_fragment")
        else {
            self.device = nil
            self.commandQueue = nil
            self.pipelineState = nil
            self.ciContext = nil
            return
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        self.device = device
        self.commandQueue = device.makeCommandQueue()
        self.pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor)
        self.ciContext = CIContext(mtlDevice: device)
    }

    /// 给定纸张样式与目标点尺寸+屏幕 scale，返回渲染好的纹理图。命中缓存直接返回；
    /// Metal 不可用（理论上不会在 iOS 上发生）时返回 nil，调用方回退纯色。
    func image(for style: PaperStyle, size: CGSize, scale: CGFloat) -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let pixelWidth = max(1, Int((size.width * scale).rounded()))
        let pixelHeight = max(1, Int((size.height * scale).rounded()))
        let key = "\(style.id)_\(pixelWidth)x\(pixelHeight)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = render(style: style, pixelWidth: pixelWidth, pixelHeight: pixelHeight, scale: scale) else {
            return nil
        }
        cache.setObject(image, forKey: key)
        return image
    }

    private func render(style: PaperStyle, pixelWidth: Int, pixelHeight: Int, scale: CGFloat) -> UIImage? {
        guard let device, let commandQueue, let pipelineState, let ciContext else { return nil }

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: pixelWidth, height: pixelHeight, mipmapped: false)
        textureDescriptor.usage = [.renderTarget, .shaderRead]
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else { return nil }

        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = texture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].storeAction = .store
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else { return nil }

        var params = style.shaderParams(aspect: Float(pixelWidth) / Float(max(pixelHeight, 1)))
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(&params, length: MemoryLayout<PaperShaderParams>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        guard let ciImage = CIImage(mtlTexture: texture, options: [.colorSpace: CGColorSpaceCreateDeviceRGB()]) else {
            return nil
        }
        // Metal 纹理坐标系原点在左上，CIImage 默认按左下解释坐标，渲染出的图会上下颠倒，这里翻回来。
        let flipped = ciImage.transformed(by: CGAffineTransform(scaleX: 1, y: -1)
            .translatedBy(x: 0, y: -ciImage.extent.height))
        guard let cgImage = ciContext.createCGImage(flipped, from: flipped.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
}
