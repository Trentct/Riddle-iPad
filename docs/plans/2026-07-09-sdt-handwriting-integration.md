# SDT 轨迹字库接入 实现计划

**需求（Trent 确认版）**：把 handwriting-foundry 产出的 neat-C002 轨迹字库（6763 字 × 2 变体，1.42MB）接入 App，作为第六款回信笔迹「手泽」上线，供 Trent 真机验证"轨迹路线"效果。本版**只上手泽这一款 SDT 手迹**，不碰人格声线/落款/纸张扩展。

**核心变化**：中文回信有两种数据源——① 字体骨架化（现有五款）② SDT 轨迹（手泽）。手泽选中时，中文渲染跳过 rasterize→thin→trace，直接用轨迹点；字库外的字（生僻字/标点/数字/英文）回落到字体路径。

**字库来源**：`~/Desktop/项目/handwriting-foundry/out/pack/` 的 `neat-C002.bin.gz` + `neat-C002.index.json.gz` + `manifest.json`。格式见该项目 `export/FORMAT.md`（unit em-box + u16 量化，含 Swift 解码骨架）。

## Global Constraints

- iPadOS 17+，仅 iPad；零第三方依赖（gzip 用系统 `Compression` framework，非 zlib）
- 字库 3 个文件放 `Riddle/HandBank/`，作为 bundle resource（project.yml 加 resources 声明）
- 手泽 id `"shouze"`，进 ReplyHands.all（第六位），圈选页第六行
- 现有 30 个测试保持通过；Script/Oracle 逻辑不动
- 每任务 commit；测试命令：`xcodebuild test -scheme Riddle -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4),OS=17.4' -quiet`

---

### Task 1: HandBank 解码器

**Files:** Create `Riddle/HandBank/HandBank.swift`、`Riddle/HandBank/neat-C002.bin.gz`、`neat-C002.index.json.gz`、`manifest.json`（从 foundry 拷贝）；Modify `project.yml`(resources)；Test `RiddleTests/HandBankTests.swift`

**Interfaces (produces):**
```swift
struct HandBank {
    /// 加载 bundle 内指定 style 的字库；失败返回 nil（缺文件/版本不符）
    static func load(style: String) -> HandBank?
    /// 返回该字的某变体轨迹（unit em-box [0,1] 点，已按笔顺分笔）；字库无此字返回 nil
    func strokes(for char: Character, variant: Int) -> [[CGPoint]]?
    var contains: (Character) -> Bool { get }   // 或 func contains(_:) -> Bool
}
```
- 按 FORMAT.md 实现：gunzip（系统 Compression framework，`.zlib`/gzip header 处理）→ 解 index JSON（`[String:[VariantRef]]`）→ 按 offset/length 切 bin、按 uint8 n_strokes / uint16 n_points / uint16×2 量化点解析 → CGPoint(x/65535, y/65535)
- 校验 manifest.format_version == 1，否则 load 返回 nil
- 缓存：load 一次常驻（单 style ~2.7MB 解压后 bin 常驻内存，可接受）
- **测试**（真实字库文件参与）：load 成功且 contains("哈")==true；strokes("哈",0) 非空、每笔点在 [0,1]、笔数与 index 的 n_strokes 一致；contains("𰻝")==false（超字库字）；variant 越界返回 nil；load 不存在的 style 返回 nil
- 全量测试通过后 commit

### Task 2: QuillLayer 轨迹数据源 + 手泽入列 + 回落

**Files:** Modify `Riddle/QuillLayer.swift`、`Riddle/ReplyHand.swift`、`Riddle/HandPickerView.swift`(样字渲染)、`RiddleApp.swift`(bank 注入)；Test `RiddleTests/ReplyHandTests.swift`

**Interfaces (consumes):** HandBank（Task 1）、Script.smoothPath/humanize（现有）

- **ReplyHand 扩展**：加 `let bankStyle: String?`（字体款为 nil，手泽为 "neat-C002"）。ReplyHands.all 追加第六位：id "shouze"、name「手泽」、fontName（回落用，取 LXGWWenKai-Regular）、bankStyle "neat-C002"。默认仍 xiaxing。
- **QuillLayer 双路渲染**（`write` 内，逐字级决策）：
  - 当前 hand 有 bankStyle 且 HandBank 加载成功且 `bank.contains(char)`：取 `bank.strokes(for: char, variant: 随机0/1)` → 点从 em-box 映射到该字的页面 glyph box（字号/行高沿用现有 rasterPx 体系换算：em-box×glyphSize + 字位偏移）→ humanize → smoothPath → CAShapeLayer strokeEnd 逐笔回放（复用现有动画）
  - 否则（字体款，或手泽遇字库外字符）：走现有 rasterize→thin→trace→simplify→humanize 路径
  - **注意逐字混排**：一句"你好 A"里"你好"走轨迹、"A"走字体——按字符切分，各字独立选路，共用同一行光标推进（现有 QuillLayer 已是逐字光标，扩展为"每字先判数据源"）
  - 轨迹字的行内定位：SDT 轨迹是单字 em-box，需要横向逐字排布（字宽用 em-box 归一宽 × 字号 + 字距），不能再用整行光栅化的 wrap。**这是本任务最复杂点**：手泽路径需要自己的逐字排版（字号固定、按字推进 x、超行宽换行），字体路径保持原样。
- **HandPickerView**：手泽那行样字（"见字如面，落墨为凭。"）也走轨迹渲染（同一套逐字排版），生僻标点回落——确保圈选页第六行展示的就是真实手泽笔迹
- **RiddleApp/注入**：App 启动时 `HandBank.load(style:"neat-C002")` 一次，注入给 QuillLayer 和 HandPickerView 可访问的位置（可用与 ReplyHandStore 并列的单例 `HandBankStore.shared`，@MainActor，持有已加载 bank，缺失时 nil→全回落字体）
- **测试**：ReplyHands.all 含手泽且顺序正确、bankStyle 字段正确；HandBankStore 加载真实字库后 contains 常用字；（轨迹排版是 UI，靠截图验收）
- 模拟器验证：启动圈选页截图（第六行手泽应为轨迹笔迹，明显区别于上五行）；选手泽后写"你好世界"截图看回信轨迹渲染
- 全量测试通过后 commit

### Task 3: 圈选页六行布局 + 手泽人名 + 真机验收准备

**Files:** Modify `Riddle/HandPickerView.swift`、`Riddle/ReplyHand.swift`(name)

- 六行布局：确认 6 行 × 行高/间距在 iPad 竖屏放得下（现 5 行 576pt，加一行约 690pt，1194pt 高度够）；圈选容差保持 ≥28pt
- 手泽这行写什么：本版**仍写样句**（与其他行一致「见字如面，落墨为凭。」），人名方案（沈砚/云迟/…/手泽）留给后续"人格化 feature"，本版不引入人名——保持范围最小、只验证轨迹效果
- 截图验收：六行、手泽行为轨迹笔迹、无裁切
- commit

**遗留（记录不做）**：人格声线、落款圈退、flowing 第二风格、罕见字标点的轨迹化——均后续 feature。
