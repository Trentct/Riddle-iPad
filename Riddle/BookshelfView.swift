import SwiftUI

/// 首页书架：三本角色封面书立在书桌上，点一本即选定该角色（`onOpen`）。
/// `bookNS` 是 RootView 持有的 matchedGeometryEffect 命名空间——被点的那本书封挂上
/// `.matchedGeometryEffect(id: hand.id, in: bookNS)`，与书写页容器共用同一个 id，翻开转场时
/// SwiftUI 据此把帧从"书架小书封"插值放大到"全屏纸页"（见 RiddleApp.swift RootView）。
/// 书架层允许点击选书（有意松绑——书架是 meta 层，纸面书写层仍纯笔）。
struct BookshelfView: View {
    var bookNS: Namespace.ID
    let onOpen: (ReplyHand) -> Void

    var body: some View {
        GeometryReader { geo in
            let bookWidth = min(240, geo.size.width * 0.22)
            let bookHeight = bookWidth * 1.5

            ZStack {
                deskBackground

                VStack(spacing: 0) {
                    Text("取下一本，与谁落墨")
                        .font(.custom(ReplyHands.shouze.fontName, size: 26))
                        .foregroundStyle(Color(hex: 0xe9dcc0))
                        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                        .padding(.top, max(32, geo.size.height * 0.06))

                    // 上下等权 Spacer：书架行居中落在标题下方的可用空间里（而非贴底堆一坨空白在最上头）。
                    Spacer(minLength: 0)

                    HStack(alignment: .bottom, spacing: bookWidth * 0.22) {
                        ForEach(ReplyHands.all) { hand in
                            Button {
                                onOpen(hand)
                            } label: {
                                BookCover(hand: hand, coverColor: BookCoverPalette.colors[hand.id] ?? .brown)
                                    .frame(width: bookWidth, height: bookHeight)
                                    .matchedGeometryEffect(id: hand.id, in: bookNS)
                                    .shadow(color: .black.opacity(0.6), radius: 16, x: 8, y: 20)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(hand.name)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .ignoresSafeArea()
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
    }

    /// 书桌背景：暖木渐变 + 手绘感木纹（Canvas 画多条宽窄/明暗不一的横纹，避免机械平铺感）+
    /// 书本身后一团暖光池（呼应"灯下摊开一本书"的场景）+ 保留原有暗角，三层叠出材质感而非平板深棕。
    private var deskBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x2e1e13), Color(hex: 0x54381f), Color(hex: 0x261a10)],
                startPoint: .top, endPoint: .bottom
            )
            WoodGrainOverlay()
            // 暖光池：中心略低于画面正中（书本所在的下半区），模拟灯光洒在书桌上。
            RadialGradient(colors: [Color(hex: 0xd9a25c).opacity(0.22), .clear],
                            center: UnitPoint(x: 0.5, y: 0.7), startRadius: 40, endRadius: 520)
            RadialGradient(colors: [.clear, .black.opacity(0.55)],
                            center: .center, startRadius: 260, endRadius: 900)
        }
        .ignoresSafeArea()
    }
}

/// 手绘木纹：用 `Canvas` 画一组横纹，宽度与明暗按正弦函数错落（而非等距等透明度的机械横条），
/// 读出来接近木板纹理的不规则感；纯几何计算、无随机数，重复渲染结果稳定不闪烁。
private struct WoodGrainOverlay: View {
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            var i = 0
            while y < size.height {
                let stripHeight = 4 + CGFloat((i * 5) % 7)
                let wave = abs(sin(Double(i) * 0.55))
                if i.isMultiple(of: 2) {
                    let opacity = 0.03 + 0.05 * wave
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: stripHeight)),
                                 with: .color(.black.opacity(opacity)))
                } else {
                    let opacity = 0.02 + 0.03 * wave
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: stripHeight)),
                                 with: .color(Color(hex: 0xffdca8).opacity(opacity)))
                }
                y += stripHeight
                i += 1
            }
        }
    }
}
