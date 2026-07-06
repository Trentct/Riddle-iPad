# Riddle-iPad 设计文档

日期：2026-07-06
状态：待 Trent 确认

## 一句话

把 MaximeRivest/Riddle（reMarkable 上的「汤姆·里德尔日记本」）移植成 iPad + Apple Pencil 原生 App：用笔写字 → 字迹被纸"喝掉" → AI 用手写体一笔一笔写回信。

## 目标与边界

- **定位**：纯魔法体验 demo，不设人格养成、不做 journaling 工具。定位后置。
- **成功标准**：在 Trent 自己的 iPad 上丝滑跑通，拍出可发社媒（小红书/推特）的演示视频。不上架、不 TestFlight。
- **语言**：中英双语。中英文统一走同一套手写合成管线（见下），不再分两种渲染策略。
- **明确不做**（YAGNI）：书写沙沙声、翻页/多页历史、设置界面、持久化、账号体系、多设备适配。

## 借用 MaximeRivest/Riddle（MIT）的部分

1. **整体链路**：笔迹 → 停笔 2.8s 提交 → 整页渲染 PNG → 视觉 LLM → 逐句流式返回 → 手写合成逐笔回放。
2. **手写合成算法**（`riddle/src/script.rs`，移植为 Swift）：
   文本光栅化（任意 TTF）→ Zhang-Suen 细化成 1px 骨架 → 骨架追踪成有序折线 → 按 x 排序逐笔回放。
   该方法对中文字体同样有效（非真笔顺，视觉上像书写）。
3. **Persona prompt**（`riddle/src/oracle.rs` 的 `PERSONA`）：日记本人格、"永远用写信人的语言回复"、"绝不提图片/AI"、"字迹不清就说墨水晕开"、回复一到三句。
4. **交互决策**：回复写完后自己也淡去；错误也在人设内表达。

合规：新仓库 README 与移植文件头部注明算法源自 MaximeRivest/Riddle (MIT)。不 fork——原项目是 Rust/C++ 跑 reMarkable Linux，无一行代码可直接复用。

## 交互流程（一个回合）

1. App 启动即全屏一张"纸"，无任何 UI 元素。
2. 用户用 Pencil 书写（PencilKit 钢笔笔刷）。
3. 停笔 2.8s → 整页渲染 PNG → 发给 Oracle（流式）。
4. 同时「纸喝墨水」：用户笔迹按书写顺序逐笔淡去（约 2.5~4s，掩盖 API 首句延迟）。
5. 回信逐句到达，每句经手写合成变成笔画，在纸上一笔一笔写出。
6. 墨迹留驻 8s（或用户再次落笔立即让位），然后回信也淡去，纸回到空白。
7. 会话上下文保留在内存（多轮记忆），退出 App 即忘。

## 架构

```
DiaryView (SwiftUI)          纸面 + 装配
  ├── InkCanvas (PKCanvasView)   收笔迹
  ├── FadeLayer                  字迹淡去动画
  └── QuillLayer                 AI 逐笔书写动画
TurnEngine                   回合状态机（唯一协调者）
Oracle                       LLM 流式客户端（OpenAI 兼容）
Script                       手写合成纯函数（rasterize/thin/trace/wrap）
```

- **TurnEngine** 状态机：`idle → writing → drinking（淡去+等首句）→ replying（逐笔写）→ lingering（留驻）→ idle`。停笔计时、状态切换、messages 历史都在这里。模块间只通过 TurnEngine 通信。
- **InkCanvas**：封装 PKCanvasView。对外仅两件事：报告"新笔画/停笔"；交出 PKDrawing（逐笔数据 + 整页 PNG）。
- **FadeLayer**：每笔渲染为独立 CALayer，按书写时序逐笔 alpha 淡出 + 高斯模糊。
- **QuillLayer**：Script 输出的折线 → CAShapeLayer + strokeEnd 动画，按序播放，恒定笔速。
- **Script**：三个纯函数 + wrap（自动换行），无 UI 依赖，唯一带单元测试的模块（拿原版 Rust 测试用例对拍：如 "Yes, Harry?" 96px 应产出非空笔画集、总点数 > 200、细化后墨点 < 细化前 1/3）。
- **Oracle**：见下节。

## Oracle（LLM 接入）

- **服务商：Kimi / Moonshot**（Trent 已有 key）。OpenAI 兼容 `POST {base}/chat/completions`，`stream: true`。
- 视觉模型具体型号实现时实测确定（`kimi-latest` / moonshot vision 系），只是配置项。
- 客户端按 OpenAI 兼容格式实现（与原版 Riddle 一致），`base_url + model + api_key` 三项可配 → 未来切任何兼容服务零成本。
- 请求：`system` = persona prompt；`messages` = 历史轮次 + 本轮 `{image_url: data URI(整页PNG), text: "(纸上浮现了新的墨迹)"}`。
- 流式 SSE 解析：攒 `delta.content` 增量，遇 `。？！.?!` 切句，逐句交给 QuillLayer——笔在模型没写完时就开写，掩盖延迟。
- 识别与回复一步完成（不做本地 OCR）：图直接进多模态模型，附带能回应涂鸦/画图。
- **Key 管理**：`Secrets.xcconfig`（gitignore）经 Info.plist 注入。仅本机 demo，不需要更重的方案。

## 动画与魔法感参数（初始值，真机调）

| 项 | 参数 |
|---|---|
| 纸面 | 米白 #F5F0E8 + 细纹理贴图 + 轻微暗角；隐藏状态栏/Home indicator；横竖屏均可（拍摄以竖屏为主） |
| 用户墨水 | PencilKit .pen，蓝黑 #1A1A2E，保留压感 |
| 喝墨水 | 按书写序逐笔启动，笔间错开 80ms；单笔 1.2s：alpha 1→0 + 模糊 0→3pt |
| 回信书写 | 路径速度 ~900pt/s，笔画间 40ms，句间 350ms（蘸墨感）；墨色 #0F0F23；从页面上 1/3 起笔，自动换行 |
| 留驻与消散 | 写完留驻 8s 或用户落笔即让位；回信淡去速度放慢 1.5×（人格暗示） |
| 字体 | 英文 Dancing Script（OFL）；中文霞鹜文楷（OFL）；按回复是否含 CJK 字符选字体 |

**错误的魔法化**：网络/API 失败 → 手写浮现"墨迹晕开了，什么也没显现……"；空白提交 → 忽略不进回合。

## 项目结构

```
~/Desktop/项目/Riddle-iPad/
├── project.yml                # XcodeGen 生成 .xcodeproj
├── Secrets.xcconfig           # API key（gitignore）
├── docs/                      # 本文档
├── Riddle/
│   ├── RiddleApp.swift
│   ├── DiaryView.swift
│   ├── TurnEngine.swift
│   ├── InkCanvas.swift
│   ├── FadeLayer.swift
│   ├── QuillLayer.swift
│   ├── Oracle.swift
│   ├── Script/                # + 单元测试
│   ├── Fonts/                 # DancingScript.ttf、LXGWWenKai.ttf
│   └── Resources/             # 纸纹理
└── README.md                  # 致谢 MaximeRivest/Riddle (MIT)
```

工具链：Xcode 26.6（已装）+ XcodeGen（brew install xcodegen）。真机：Trent 的 iPad + Apple Pencil。

## 风险与对策

| 风险 | 对策 |
|---|---|
| 中文骨架化在小字号下断笔/粘连 | 光栅化用大字号（≥128px）再整体缩放回目标大小 |
| Moonshot 首句延迟盖不住淡去动画 | 淡去动画时长可拉长（笔间隔可调）；或换更快模型（一行配置） |
| 手写照片识别不准 | persona 已设"字迹不清就说墨水晕开"，错误在人设内 |
| CAShapeLayer 笔画数过多（长回复）卡顿 | 回复限一到三句（persona 控制）；每句渲染完合并为位图 layer |
