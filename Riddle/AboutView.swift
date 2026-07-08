import SwiftUI
import StoreKit

/// 一条开源/字体致谢条目：名称 + 授权 + 用途说明。`Attributions.all` 是唯一真源——AboutView 渲染用它，
/// AboutViewTests 断言用它——避免以后加字体/换依赖时文案漏更新却没人发现。
struct AttributionItem: Identifiable, Equatable {
    let id: String
    let name: String
    let license: String
    let note: String
}

/// 致谢清单：法务要求，不是可选项。四类来源——① 算法与 persona 出处 ② 实际渲染在用的两款字体
/// ③ 手泽轨迹字库背后的生成模型 ④ 随包但当前未被任何回信角色使用的字体（字体实验遗留，仍需保留授权记录）。
/// 各条 license 结论见仓库 `.superpowers/sdd/font-candidates/licenses.md` 与 `font-matrix/licenses.md`、
/// 以及 `README.md`/`LICENSE`（算法与字体来源）、`~/Desktop/项目/handwriting-foundry/SDT/LICENSE`（SDT）。
enum Attributions {
    static let all: [AttributionItem] = [
        AttributionItem(
            id: "riddle-origin",
            name: "MaximeRivest/Riddle",
            license: "MIT",
            note: "手写合成算法（光栅化→细化→骨架追踪）与日记本 persona 的原始出处（reMarkable 版）；本 App 是其 iPad 移植。"),
        AttributionItem(
            id: "lxgw-wenkai",
            name: "LXGW WenKai 霞鹜文楷",
            license: "SIL Open Font License 1.1",
            note: "归野、沈砚两款回信笔迹使用的中文字体。"),
        AttributionItem(
            id: "dancing-script",
            name: "Dancing Script",
            license: "SIL Open Font License 1.1",
            note: "Ashford 回信笔迹使用的英文字体。"),
        AttributionItem(
            id: "sdt",
            name: "dailenson/SDT（Style-Disentangled Transformer）",
            license: "MIT",
            note: "「手泽」笔迹的轨迹字库由此模型生成——归野默认笔迹背后的手写合成引擎。"),
        AttributionItem(
            id: "bundled-unused-fonts",
            name: "演示夏行楷 · 云峰寒蝉体 YFHCT · 龙藏体 Long Cang · 流江毛草 Liu Jian Mao Cao",
            license: "作者声明可商用嵌入（前两款）/ SIL OFL 1.1（后两款）",
            note: "随包但当前未被任何回信角色使用（字体实验遗留），一并致谢并保留授权记录。"),
    ]
}

/// 隐私政策/条款外链。FLAG: Trent 待定——占位 URL，需要 Trent 实际托管页面后替换
/// （见 docs/app-store/SUBMISSION_CHECKLIST.md「隐私政策 URL 托管」一项）。
enum AboutLinks {
    static let privacyPolicyURL = URL(string: "https://trentct.github.io/riddle/privacy")!
    static let termsURL = URL(string: "https://trentct.github.io/riddle/terms")!
}

/// 关于/设置页——App Store 上架的法务必需项集中于此：音效开关、恢复购买、开源与字体致谢、
/// 隐私政策与条款外链。水墨纸面风格与其余界面一致，但正文用系统字体保证长文字可读性
/// （标题/引导语才用手写字体——法务文本不该为了"入戏"牺牲可读性）。
struct AboutView: View {
    let onDismiss: () -> Void

    @ObservedObject private var soundStore = SoundStore.shared
    @ObservedObject private var storeManager = StoreManager.shared
    @State private var isRestoring = false
    @State private var restoreDone = false

    private var versionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        ZStack {
            Color(Ink.paperColor).ignoresSafeArea()
            Image(uiImage: PaperTexture.tile)
                .resizable(resizingMode: .tile)
                .opacity(0.05)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    Divider().opacity(0.3)
                    soundSection
                    Divider().opacity(0.3)
                    restoreSection
                    Divider().opacity(0.3)
                    legalSection
                    Divider().opacity(0.3)
                    attributionSection
                }
                .padding(28)
                .padding(.top, 20)
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color(Ink.quillColor))
                            .opacity(0.55)
                            .padding(16)
                    }
                    .accessibilityLabel("关闭")
                }
                Spacer()
            }
        }
        .foregroundStyle(Color(Ink.quillColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Riddle")
                .font(.custom(ReplyHands.shouze.fontName, size: 34))
            Text("版本 \(versionString)")
                .font(.system(size: 13))
                .opacity(0.6)
            Text("纸会记得，墨会淡去，回信总在。")
                .font(.custom(ReplyHands.wenkai.fontName, size: 17))
                .opacity(0.75)
                .padding(.top, 4)
        }
    }

    private var soundSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("声音")
            Toggle(isOn: Binding(
                get: { soundStore.isEnabled },
                set: { soundStore.setEnabled($0) }
            )) {
                Text("书写笔尖音效")
                    .font(.system(size: 15))
            }
            .tint(Color(Ink.quillColor))
        }
    }

    private var restoreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("购买")
            Button {
                Task {
                    isRestoring = true
                    await storeManager.restore()
                    isRestoring = false
                    restoreDone = true
                }
            } label: {
                HStack {
                    Text("恢复购买")
                        .font(.system(size: 15))
                    if isRestoring {
                        ProgressView().tint(Color(Ink.quillColor))
                    }
                }
            }
            .disabled(isRestoring)

            if restoreDone {
                Text(storeManager.isUnlocked ? "已恢复无限解锁。" : "未找到可恢复的购买记录。")
                    .font(.system(size: 13))
                    .opacity(0.6)
            }
            if let error = storeManager.lastError {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.red.opacity(0.7))
            }
        }
    }

    private var legalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("隐私与条款")
            Link(destination: AboutLinks.privacyPolicyURL) {
                Text("隐私政策")
                    .font(.system(size: 15))
                    .underline()
            }
            Link(destination: AboutLinks.termsURL) {
                Text("使用条款")
                    .font(.system(size: 15))
                    .underline()
            }
        }
    }

    private var attributionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("致谢")
            ForEach(Attributions.all) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .semibold))
                    Text(item.license)
                        .font(.system(size: 12))
                        .opacity(0.55)
                    Text(item.note)
                        .font(.system(size: 12))
                        .opacity(0.7)
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .opacity(0.5)
            .textCase(.uppercase)
    }
}
