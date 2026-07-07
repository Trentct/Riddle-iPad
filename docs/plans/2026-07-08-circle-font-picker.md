# 启动圈选笔迹 实现计划

**需求（Trent 确认版）**：App 启动即进入"圈选页"——纸上竖排四行样字，每行用一款候选笔迹写同一句话；用户用笔（或手指）把想要的那行**圈起来**即选中，全局生效（所有纸的中文回信都用它），随后墨迹淡去进入书写纸面。每次启动都先经过圈选页（开门仪式）。

**候选四款**（中文回信笔迹，均已核许可）：
| id | 名称 | 字体 | 性格 |
|---|---|---|---|
| wenkai | 文楷 | LXGWWenKai-Regular（已入包） | 工整 |
| xiaxing | 夏行楷 | 演示夏行楷（.superpowers/sdd/font-candidates/ttf/） | 行楷·默认 |
| longcang | 龙藏 | LongCang-Regular（.superpowers/sdd/font-matrix/ttf/） | 草意 |
| maocao | 流江毛草 | LiuJianMaoCao-Regular（同上） | 狂草 |

英文回信不受影响（Dancing Script）。圈选判定宽容：不要求闭合，按笔迹包围盒与行框交叠面积最大者胜；选中行有墨迹反馈；无任何按钮。

---

### Task 1: 字体入包 + ReplyHandStore + QuillLayer 接线

**Files:** Create `Riddle/ReplyHand.swift`；Modify `project.yml`(UIAppFonts)、`Riddle/QuillLayer.swift`(font(for:))；Copy 3 个 ttf 到 `Riddle/Fonts/`；Test `RiddleTests/ReplyHandTests.swift`

**Interfaces (produces):**
```swift
struct ReplyHand: Identifiable, Equatable { let id: String; let name: String; let fontName: String }
enum ReplyHands { static let all: [ReplyHand] /* wenkai, xiaxing, longcang, maocao 顺序 */ }
@MainActor final class ReplyHandStore: ObservableObject {
    static let shared: ReplyHandStore
    @Published private(set) var current: ReplyHand   // 默认 xiaxing
    func select(_ id: String)                        // 持久化 UserDefaults "replyHandID"
    init(defaults: UserDefaults = .standard)
}
```
- QuillLayer `font(for:)`：CJK → `UIFont(name: ReplyHandStore.shared.current.fontName, size: rasterPx)`，英文分支不变
- ttf 的 PostScript 名以运行时 `UIFont.familyNames` 实测为准（夏行楷预计 `SlideXiaxing` 系、龙藏 `LongCang-Regular`、毛草 `LiuJianMaoCao-Regular`），写测试断言四款全部可加载
- 测试：四款字体可加载；store 默认 xiaxing；select 持久化 roundtrip（隔离 UserDefaults suite）
- 全量测试通过后 commit

### Task 2: 圈选页 + 启动流程

**Files:** Create `Riddle/HandPickerView.swift`；Modify `Riddle/RiddleApp.swift`（RootView 相位切换）；Test `RiddleTests/CirclePickTests.swift`

**Interfaces (produces):**
```swift
enum CirclePick {  // 纯函数，可测
    /// 笔迹包围盒 vs 各行 frame，返回交叠面积最大且 >0 的行号
    static func pickRow(strokeBounds: CGRect, rowFrames: [CGRect]) -> Int?
}
struct HandPickerView: View { let onPicked: (ReplyHand) -> Void }
```

**HandPickerView 组成**：
- 背景复用当前纸样式（Color(Ink.paperColor) + PaperTexture + 暗角，同 DiaryView 背景层）
- 顶部一行小字引导（手写体渲染）："圈选一种字迹"
- 四行样字：每行把「哈利波特，真是个有趣的名字」经 Script 管线（rasterize→thin→trace→humanize）渲染成 UIImage（静态、该行自己的字体、Ink.quillColor），行高 ~64pt、行间距 ~40pt，记录各行 frame
- 顶层盖一个 PKCanvasView（`drawingPolicy = .anyInput` 双端一致——护栏：手指等价；工具 PKInkingTool(.pen, Ink.userColor, 3)）
- 判定：`canvasViewDrawingDidChange` 去抖 0.6s 后取整个 drawing 的 bounds → `CirclePick.pickRow`；命中：该行图片短暂加深/放大 1.03 反馈 0.4s → 调 `onPicked(hand)`；未命中：用户墨迹淡出清空（FadeLayer.drink 复用）
- 选中转场：整页墨迹与样字淡出（opacity 0.35s）后由 Root 切相位

**RiddleApp/RootView**：
```swift
@main struct RiddleApp: App { WindowGroup { RootView() } }
struct RootView: View {
    @State private var phase: Phase = .picking
    enum Phase { case picking, writing }
    // picking: HandPickerView { hand in ReplyHandStore.shared.select(hand.id); withAnimation { phase = .writing } }
    // writing: DiaryView()（不改）
}
```
- 每次冷启动都从 .picking 开始（需求明确：开门仪式）
- 测试：pickRow 三态（命中最大交叠行/零交叠返回 nil/跨两行取面积大者）
- 模拟器验证：启动截图见四行样字；（圈选手势模拟器可用鼠标画圈验证——.anyInput）；选中后进入纸面截图
- 全量测试通过后 commit

**遗留开放项（记录不实现）**：进入纸面后无法返回圈选页（当前仅重启）——待"书桌/折角"上线后统一承接。
