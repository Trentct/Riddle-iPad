# 首页书架 实现计划

**需求（Trent 定稿）**：首页从"三行署名字"升级为**三本精致封面书立在书桌上**。点一本 → 书以 `matchedGeometryEffect` 放大展开（Apple Books 式共享元素转场）→ 进入那个人的书写页。返回沿用现有"圈落款"。

**技术方案（Trent 拍板）**：`matchedGeometryEffect` 做书架→纸页转场（不手写 CATransform3D）；封面用生成好的三张 Logo（`Riddle/Covers/{guiye,shenyan,ashford}.png`，透明底）+ 各自笔迹渲染的名字；`ScribbleCircle` 保留给纸面圈落款，书架用点击。

## 现状

- `RiddleApp.swift` RootView：`.picking`（HandPickerView）↔ `.writing`（DiaryView）两相位。
- `HandPickerView`：当前三行角色署名 + 圈选。**本 feature 用书架 BookshelfView 替换它作为 .picking 的内容**。
- `ReplyHands.all`：三角色 shouze/归野、wenkai/沈砚、ashford/Ashford，各有 name、fontName、bankStyle、persona。
- 名字笔迹渲染：`HandSampleRenderer`（HandPickerView 内）已能按角色渲染文字（手泽走轨迹、其余走字体）——书封名字复用它。
- `PaperMetalView`：纸张材质（书桌背景可用深色变体或木纹色）。
- 落款 + 圈落款返回：DiaryView 已实现，不动。

## Global Constraints

- 三张封面图放 `Riddle/Covers/`，sources glob 自动作为 resource（同 Fonts/HandBank 机制，验证）。
- 保持 93 测试通过；DiaryView/TurnEngine/圈落款返回逻辑不动。
- 书架层允许**点击**选书（有意松绑：书架=meta层如从书架抽书；纸面层仍纯笔）。手指点击即可。
- 每任务 commit；测试命令 `xcodebuild test -scheme Riddle -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4),OS=17.4'`。

---

### Task 1: Book 封面组件 + BookshelfView（静态书架）

**Files:** Create `Riddle/BookshelfView.swift`、`Riddle/BookCover.swift`；Modify `RiddleApp.swift`(RootView .picking → BookshelfView)；Test `RiddleTests/BookshelfTests.swift`

**产出接口：**
```swift
struct BookCover: View {          // 单本书封（书架态）
    let hand: ReplyHand           // 角色
    let coverColor: Color         // 气质色：归野暖褐/沈砚墨青/Ashford酒红
    // 组成：气质色书封(圆角+书脊高光+皮革纹) + 中央 Logo(Covers/<id>.png) + 下方角色名(该角色笔迹渲染) + 烫金边框
}
struct BookshelfView: View {
    let onOpen: (ReplyHand) -> Void   // 点书回调
}
```
- 三本书横向排列在书桌上（暖木/深色背景，可用 PaperMetalView 深色参数或纯木色渐变 + 暗角 + 桌面阴影），立体投影 `.shadow`。
- 每本：`coverColor` 底 + 圆角 `4/8/8/4` + 左书脊高光条 + Logo 图居中偏上 + 名字（复用 HandSampleRenderer 渲染该角色 name，缩到书封宽）+ 内描金边框。
- 顶部一行小字引导（手写体渲染）："取下一本，与谁落墨"。
- coverColor 映射：guiye `#7a5638`、shenyan `#2f4038`、ashford `#5a2b28`（与 Logo 提示词一致）。作为 ReplyHand 的扩展字段或 BookshelfView 内常量表——放常量表（避免动 ReplyHand，颜色是 UI 关注点）。
- 点击整本书 → `onOpen(hand)`。
- **测试**：三本书对应 ReplyHands.all 三角色、顺序一致；coverColor 表三色齐全；Covers/ 三图能从 bundle 加载（`UIImage(named:)` 非 nil）。
- 模拟器截图 `.superpowers/sdd/bookshelf.png`：三本封面书立在书桌上，Logo+名字可见。
- commit

### Task 2: 翻开转场（matchedGeometryEffect）+ 接入书写页

**Files:** Modify `Riddle/RiddleApp.swift`(RootView 相位+namespace)、`Riddle/BookshelfView.swift`；Test 手动截图

- RootView 增加 `@Namespace bookNS`，三相位或用状态：`.shelf`（书架）→ `.opening`（转场中，可选中间态）→ `.writing`（DiaryView）。
- 选中的书用 `.matchedGeometryEffect(id: hand.id, in: bookNS)`：书架态是小书封，展开态是全屏纸页容器——同 id 让 SwiftUI 插值放大。`withAnimation(.spring(response:0.55, dampingFraction:0.82))` 触发。
- 展开后即 DiaryView（该角色已 select）。**可选**：展开瞬间封面 Logo/色淡出、纸面淡入（crossfade），营造"翻开"而非"生硬放大"。先做纯 matchedGeometry 放大 + crossfade；`.rotation3DEffect` 书脊铰链留作后续 polish（本版不做，记录）。
- 选书即 `ReplyHandStore.shared.select(hand.id)`（决定笔迹/persona/落款）。
- 返回：DiaryView 圈落款 → RootView 回 `.shelf`（复用现有 writing→picking 通路，改成回书架）。
- 每次冷启动从 `.shelf` 开始。
- 模拟器验证：书架截图、点书后书写页截图（`.anyInput` 模拟器可点）。
- commit

**遗留（记录不做）**：`.rotation3DEffect` 书脊 3D 掀开动画（polish）；书桌质感精修；书本 hover/长按预览。
