import SwiftUI

/// 纸张材质背景：drop-in 替代旧的 `Color(paperColor) + PaperTexture 噪点 + RadialGradient` 三层叠加。
/// 内部用 `PaperMetalRenderer` 离屏渲染一张按当前尺寸缓存好的纹理图，静态展示、不逐帧重绘。
/// 切换样式（双指翻页）时手动做一次淡入淡出，找回旧版「Color 值可动画」带来的柔和过渡——
/// 新图内容本身不是 Animatable，纯 `.animation` 修饰符对 `Image(uiImage:)` 换图没有效果。
struct PaperMetalView: View {
    let style: PaperStyle

    @State private var previousImage: UIImage?
    @State private var currentImage: UIImage?
    @State private var fadeIn: CGFloat = 1
    @State private var renderedStyleID: String?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 兜底纯色：首帧渲染完成前、或 Metal 不可用时仍有正确的纸色打底。
                Color(style.paperColor)

                if let previousImage {
                    Image(uiImage: previousImage)
                        .resizable()
                        .opacity(1 - fadeIn)
                }
                if let currentImage {
                    Image(uiImage: currentImage)
                        .resizable()
                        .opacity(fadeIn)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .onAppear { updateImage(size: geo.size, animated: false) }
            .onChange(of: style.id) { _, _ in updateImage(size: geo.size, animated: true) }
            .onChange(of: geo.size) { _, newSize in updateImage(size: newSize, animated: false) }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func updateImage(size: CGSize, animated: Bool) {
        let scale = UIScreen.main.scale
        guard let image = PaperMetalRenderer.shared.image(for: style, size: size, scale: scale) else { return }
        guard renderedStyleID != style.id || currentImage == nil else {
            // 同一样式下的尺寸变化（旋转/分屏）：直接换图，不需要淡入淡出。
            currentImage = image
            return
        }
        renderedStyleID = style.id
        if animated, currentImage != nil {
            previousImage = currentImage
            fadeIn = 0
            currentImage = image
            withAnimation(.easeInOut(duration: 0.35)) { fadeIn = 1 }
        } else {
            currentImage = image
            fadeIn = 1
        }
    }
}
