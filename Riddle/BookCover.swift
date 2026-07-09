import SwiftUI

/// 书封气质色表：与三张 Logo（`Riddle/Covers/<id>.png`）的配色提示词一致。故意不挂在 `ReplyHand` 上——
/// 颜色是书架 UI 的展示层关注点，不该进领域模型（领域模型只关心 persona/字迹，不关心怎么画）。
enum BookCoverPalette {
    static let colors: [String: Color] = [
        "shouze": Color(hex: 0x7a5638),   // 归野：暖褐
        "wenkai": Color(hex: 0x2f4038),   // 沈砚：墨青
        "ashford": Color(hex: 0x5a2b28),  // Ashford：酒红
    ]
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

/// `Covers/<file>.png` 是循环打包的松散资源文件（同 Fonts/HandBank 机制：xcodegen 的 `sources: [Riddle]`
/// glob 把非代码文件当资源整体拷进 bundle，不进 Asset Catalog）。`UIImage(named:)` 在主 bundle 里也会找
/// 松散图片文件（不仅限 Asset Catalog），但为防止某些打包路径下失效，这里做一次
/// `Bundle.main.path(forResource:ofType:)` 兜底，两条路径任一成功即可。
///
/// 注意：文件名是角色名拼音（guiye/shenyan/ashford），与 `ReplyHand.id`（shouze/wenkai/ashford）
/// 不是同一套命名——`fileNames` 显式做这层映射，不能直接拿 `hand.id` 当文件名去找。
enum CoverImage {
    private static let fileNames: [String: String] = [
        "shouze": "guiye",
        "wenkai": "shenyan",
        "ashford": "ashford",
    ]

    static func load(id: String) -> UIImage? {
        let fileName = fileNames[id] ?? id
        if let named = UIImage(named: fileName) { return named }
        guard let path = Bundle.main.path(forResource: fileName, ofType: "png") else { return nil }
        return UIImage(contentsOfFile: path)
    }
}

/// 书封版角色名样字缓存：与圈选页的 `HandSampleCache` 共用 `HandNameRenderer`（选轨迹/字体分支）与
/// `HandSampleRenderer`（实际光栅化管线），只是墨色换成烫金——书封与圈选页用途不同故各自持有一份
/// 缓存，但渲染算法完全复用，不重新实现手写渲染。
@MainActor
final class BookNameCache: ObservableObject {
    static let shared = BookNameCache()
    static let foilInk: CGColor = UIColor(red: 0.82, green: 0.66, blue: 0.33, alpha: 1).cgColor

    @Published private(set) var images: [String: UIImage] = [:]
    private var started = false

    func warm() {
        guard !started else { return }
        started = true
        let banks = Dictionary(uniqueKeysWithValues: ReplyHands.all.compactMap { hand -> (String, HandBank)? in
            guard let bankStyle = hand.bankStyle, let bank = HandBankStore.shared.bank(for: bankStyle) else { return nil }
            return (hand.id, bank)
        })
        Task.detached(priority: .userInitiated) {
            let result = Dictionary(uniqueKeysWithValues: ReplyHands.all.map { hand -> (String, UIImage) in
                (hand.id, HandNameRenderer.render(hand, bank: banks[hand.id], inkColor: Self.foilInk))
            })
            await MainActor.run { self.images = result }
        }
    }
}

/// 单本书封（书架态）：气质色底 + 圆角(4/8/8/4：书脊侧方、翻口侧圆) + 左书脊高光条 + 中央偏上 Logo +
/// 下方角色名（该角色笔迹渲染，烫金色，经 `BookNameCache`）+ 内描金边框。尺寸由外部 `.frame` 决定
/// （内部用 GeometryReader 按可用尺寸摆放元素），角落半径与描边线宽按点值写死（书封细节，不随尺寸缩放）。
struct BookCover: View {
    let hand: ReplyHand
    let coverColor: Color

    @ObservedObject private var nameCache = BookNameCache.shared

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 8,
                                bottomTrailingRadius: 8, topTrailingRadius: 4)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                shape.fill(coverColor)

                // 皮革/布纹光泽：左上高光→右下压暗的对角渐变，CSS 布纹渐变的 SwiftUI 等价物。
                shape.fill(
                    LinearGradient(colors: [.white.opacity(0.18), .clear, .black.opacity(0.28)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                // 暗角：书封边缘略压暗，让中央 Logo 更聚焦。
                shape.fill(
                    RadialGradient(colors: [.clear, .black.opacity(0.32)],
                                   center: .center, startRadius: geo.size.width * 0.25, endRadius: geo.size.width * 0.9)
                )

                // 左书脊高光条。
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(LinearGradient(colors: [.white.opacity(0.32), .clear],
                                              startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * 0.05))
                    Spacer(minLength: 0)
                }
                .clipShape(shape)

                VStack(spacing: geo.size.height * 0.04) {
                    Spacer(minLength: geo.size.height * 0.1)
                    if let logo = CoverImage.load(id: hand.id) {
                        Image(uiImage: logo)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width * 0.6)
                            .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                    }
                    if let nameImage = nameCache.images[hand.id] {
                        Image(uiImage: nameImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: geo.size.width * 0.78, maxHeight: geo.size.height * 0.14)
                    }
                    Spacer(minLength: geo.size.height * 0.12)
                }

                // 内描金边框：烫金书封常见的双线细节。
                shape
                    .strokeBorder(
                        LinearGradient(colors: [Color(hex: 0xe8c97a), Color(hex: 0x9c7a34), Color(hex: 0xe8c97a)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: max(1, geo.size.width * 0.012)
                    )
                    .padding(geo.size.width * 0.045)
            }
            .clipShape(shape)
        }
        .onAppear { nameCache.warm() }
    }
}
