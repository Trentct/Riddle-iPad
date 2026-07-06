# 纸张样式系统 实现计划

**起点**：Trent 希望可选纸张样式（讨论于 2026-07-07，交互定为双指横滑，排除了长按浮现与设置页方案——保持"无 UI"原则）。
**Goal:** 四款纸张样式，双指左右横滑翻纸切换，选择持久化；墨色随纸联动。

## 样式定义（PaperStyle）

| id | 名称 | 纸色 | 用户墨 | 回信墨 | 纹理/元素 |
|---|---|---|---|---|---|
| plain | 素笺（默认，现状） | #F2EDE1 | #1A1A2E | #0F0F23 | 现有噪点 0.05 |
| parchment | 羊皮纸 | #EAD9B0 | #402D16 | #2E1F0E | 噪点 0.09 + 暗角加深（opacity 0.16） |
| ruled | 横线信纸 | #F7F4EC | #1F3A6E | #12264A | 噪点 0.04 + 蓝灰横线 #B9C4D6 0.5pt 间距 44pt（自页面 1/3 处起，与回信行高对齐）+ 红边线 #D98B8B 1pt at x=90 |
| rice | 宣纸 | #F6F3EA | #1C1C1C | #101010 | 细噪点 0.06 + 横向拉伸纤维纹（噪点 tile 横向拉伸 4× 叠加 opacity 0.03） |

## 技术要点

- `PaperStyle` struct（id/name/paperColor/userInk/quillInk/纹理参数/是否横线），`PaperStyles.all` 数组定序；`PaperStyleStore`（@MainActor，current + cycle(±1) + UserDefaults 持久化 key "paperStyleID"）
- `Ink.userColor/quillColor/paperColor` 改为读取 store.current（保持既有调用点签名，最小化改动面）；QuillLayer/TurnEngine 已在每回合取色，天然联动；已写在纸上的旧墨不回溯变色（回合很快结束，可接受）
- **手势**：`UISwipeGestureRecognizer` left/right、`numberOfTouchesRequired = 2`，加在 PKCanvasView 上并实现 `gestureRecognizerShouldRecognizeSimultaneously` 返回 false、要求 PencilKit 绘制手势失败不必等待。注意 PKCanvasView 是 UIScrollView 子类：确认 `isScrollEnabled = false`（内容不滚动），避免双指被 pan 吃掉
- **切换动画**：背景层 crossfade 0.35s（UIView.transition on背景容器），画布内容不动
- 横线/红边线画在背景（CAShapeLayer 或 SwiftUI Path），在噪点层之下、纸色之上
- 单测（轻量）：PaperStyleStore cycle 顺序环绕 + 持久化 roundtrip（UserDefaults 注入 suite 隔离）

## 验收

1. 模拟器双指横滑（触控板双指或 Option 双点拖拽）可循环切换四款纸，方向感正确（左滑下一款、右滑上一款）
2. 每款纸的新笔迹用该纸的用户墨色；回信用该纸的回信墨色
3. 横线纸的回信恰好写在横线上
4. 杀掉 App 重开，纸张保持上次选择
5. 全部既有测试 + 新增测试通过
