import SwiftUI

/// 首页书架：三本角色封面书立在书桌上，点一本即选定该角色（`onOpen`）。
/// 本任务（Task 1）只做静态书架；Task 2 会在选书时接上 `matchedGeometryEffect` 展开转场。
/// 书架层允许点击选书（有意松绑——书架是 meta 层，纸面书写层仍纯笔）。
struct BookshelfView: View {
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
                        .padding(.top, max(40, geo.size.height * 0.08))

                    Spacer(minLength: 0)

                    HStack(alignment: .bottom, spacing: bookWidth * 0.22) {
                        ForEach(ReplyHands.all) { hand in
                            Button {
                                onOpen(hand)
                            } label: {
                                BookCover(hand: hand, coverColor: BookCoverPalette.colors[hand.id] ?? .brown)
                                    .frame(width: bookWidth, height: bookHeight)
                                    .shadow(color: .black.opacity(0.6), radius: 16, x: 8, y: 20)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(hand.name)
                        }
                    }
                    .padding(.bottom, max(48, geo.size.height * 0.14))
                }
            }
        }
        .ignoresSafeArea()
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
    }

    /// 书桌背景：暖木/深色渐变 + 暗角，书本的 `.shadow` 投在其上即产生"立在书桌上"的立体感。
    private var deskBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x2a1c12), Color(hex: 0x4a3320), Color(hex: 0x241810)],
                startPoint: .top, endPoint: .bottom
            )
            // 木纹条：细窄的水平深浅交替，暗示桌面纹理，避免纯色平板感。
            VStack(spacing: 3) {
                ForEach(0..<40, id: \.self) { i in
                    Rectangle()
                        .fill(Color.black.opacity(i.isMultiple(of: 2) ? 0.04 : 0.0))
                        .frame(height: 6)
                }
            }
            RadialGradient(colors: [.clear, .black.opacity(0.55)],
                            center: .center, startRadius: 260, endRadius: 900)
        }
        .ignoresSafeArea()
    }
}
