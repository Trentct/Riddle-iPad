# Riddle-iPad 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** iPad + Apple Pencil 版「会回信的魔法日记本」——手写 → 字迹被纸吸走 → AI 手写体逐笔回信，拍出可发社媒的 demo 视频。

**Architecture:** SwiftUI 单 App。PencilKit 收笔迹；停笔 2.8s 后整页 PNG 发给 Moonshot 视觉模型（OpenAI 兼容流式）；回信文本经「光栅化→Zhang-Suen 细化→骨架追踪」合成笔画（移植自 MaximeRivest/Riddle 的 script.rs，MIT），用 CAShapeLayer strokeEnd 逐笔回放。TurnEngine 状态机是唯一协调者。

**Tech Stack:** Swift 5 / SwiftUI / PencilKit / Core Animation / XCTest / XcodeGen。**零第三方依赖**（不引 SPM 包）。

**设计文档：** `docs/2026-07-06-riddle-ipad-design.md`（本计划的需求来源，动画参数表以它为准）

## Global Constraints

- 平台：iPadOS 17.0+，仅 iPad（`TARGETED_DEVICE_FAMILY = 2`）
- 工具链：Xcode 26.6 + XcodeGen（工程文件由 `project.yml` 生成，`.xcodeproj` 不进 git）
- 密钥：只放 `Secrets.xcconfig`（已在 .gitignore），代码经 Info.plist 读取，绝不硬编码
- 字体：DancingScript-Regular.ttf、LXGWWenKai-Regular.ttf（均 SIL OFL，可随仓库分发）
- 致谢：README 和 Script.swift 头注释注明算法移植自 MaximeRivest/Riddle (MIT)
- 每个任务结束必须 commit；单测只覆盖 Script 与 Oracle 的纯函数，UI 靠模拟器/真机手动验收
- 测试命令模板（模拟器名先用 `xcrun simctl list devices available | grep iPad | head -3` 查，替换 `<SIM>`）：
  `xcodebuild test -scheme Riddle -destination 'platform=iOS Simulator,name=<SIM>' -quiet`

---

### Task 1: 工程脚手架（XcodeGen + 字体 + 空 App 可跑）

**Files:**
- Create: `project.yml`
- Create: `Secrets.xcconfig`（不进 git）、`Secrets.xcconfig.example`
- Create: `Riddle/RiddleApp.swift`
- Create: `RiddleTests/SmokeTests.swift`
- Create: `Riddle/Fonts/DancingScript-Regular.ttf`、`Riddle/Fonts/LXGWWenKai-Regular.ttf`（下载）

**Interfaces:**
- Produces: 可编译运行的 iPad App 骨架；后续所有任务在 `Riddle/` 下加文件后重跑 `xcodegen generate` 即可入工程；`Bundle.main` 可读 `MOONSHOT_API_KEY` / `MOONSHOT_BASE_URL` / `MOONSHOT_MODEL`；两款字体可用 `UIFont(name:size:)` 加载。

- [ ] **Step 1: 安装 XcodeGen 并下载字体**

```bash
which xcodegen || brew install xcodegen
cd ~/Desktop/项目/Riddle-iPad
mkdir -p Riddle/Fonts RiddleTests
curl -fsSL -o Riddle/Fonts/DancingScript-Regular.ttf \
  "https://github.com/googlefonts/DancingScript/raw/main/fonts/ttf/DancingScript-Regular.ttf"
gh release download -R lxgw/LxgwWenKai --pattern 'LXGWWenKai-Regular.ttf' -O Riddle/Fonts/LXGWWenKai-Regular.ttf
ls -lh Riddle/Fonts/   # 两个文件都应 > 100KB；LXGW 约 19MB
```

若 DancingScript 的 URL 404，改用 `gh api repos/googlefonts/DancingScript/contents/fonts/ttf --jq '.[].name'` 查实际文件名。

- [ ] **Step 2: 写 project.yml**

```yaml
name: Riddle
options:
  bundleIdPrefix: com.trent
configFiles:
  Debug: Secrets.xcconfig
  Release: Secrets.xcconfig
targets:
  Riddle:
    type: application
    platform: iOS
    deploymentTarget: "17.0"
    sources: [Riddle]
    settings:
      base:
        TARGETED_DEVICE_FAMILY: 2
        SWIFT_VERSION: 5.9
        CODE_SIGN_STYLE: Automatic
    info:
      path: Riddle/Info.plist
      properties:
        UIAppFonts: [DancingScript-Regular.ttf, LXGWWenKai-Regular.ttf]
        UIStatusBarHidden: true
        UIRequiresFullScreen: true
        UILaunchScreen: {}
        MOONSHOT_API_KEY: $(MOONSHOT_API_KEY)
        MOONSHOT_BASE_URL: $(MOONSHOT_BASE_URL)
        MOONSHOT_MODEL: $(MOONSHOT_MODEL)
  RiddleTests:
    type: bundle.unit-test
    platform: iOS
    deploymentTarget: "17.0"
    sources: [RiddleTests]
    dependencies:
      - target: Riddle
schemes:
  Riddle:
    build:
      targets: { Riddle: all, RiddleTests: [test] }
    test:
      targets: [RiddleTests]
```

- [ ] **Step 3: 写 Secrets.xcconfig（注意 xcconfig 会把 `//` 当注释，URL 必须用 `$()` 拆开）**

`Secrets.xcconfig.example`（进 git）：

```
MOONSHOT_API_KEY = sk-换成你的key
MOONSHOT_BASE_URL = https:/$()/api.moonshot.cn/v1
MOONSHOT_MODEL = kimi-latest
```

复制为 `Secrets.xcconfig` 并让 Trent 填入真实 key：`cp Secrets.xcconfig.example Secrets.xcconfig`

- [ ] **Step 4: 写最小 App 与冒烟测试**

`Riddle/RiddleApp.swift`：

```swift
import SwiftUI

@main
struct RiddleApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Riddle")
                .persistentSystemOverlays(.hidden)
        }
    }
}

enum Secrets {
    static var apiKey: String { Bundle.main.object(forInfoDictionaryKey: "MOONSHOT_API_KEY") as? String ?? "" }
    static var baseURL: String { Bundle.main.object(forInfoDictionaryKey: "MOONSHOT_BASE_URL") as? String ?? "" }
    static var model: String { Bundle.main.object(forInfoDictionaryKey: "MOONSHOT_MODEL") as? String ?? "" }
}
```

`RiddleTests/SmokeTests.swift`：

```swift
import XCTest
@testable import Riddle

final class SmokeTests: XCTestCase {
    func testFontsLoaded() {
        XCTAssertNotNil(UIFont(name: "DancingScript-Regular", size: 96))
        XCTAssertNotNil(UIFont(name: "LXGWWenKai-Regular", size: 96))
    }
    func testSecretsPresent() {
        XCTAssertFalse(Secrets.baseURL.isEmpty)
        XCTAssertTrue(Secrets.baseURL.hasPrefix("https://"))
    }
}
```

注意：LXGW 字体的 PostScript 名可能是 `LXGWWenKai-Regular`，若测试失败，用 `UIFont.familyNames` 打印实际名字并修正测试与后续引用。

- [ ] **Step 5: 生成工程并跑测试**

```bash
cd ~/Desktop/项目/Riddle-iPad && xcodegen generate
xcrun simctl list devices available | grep iPad | head -3   # 记下一个模拟器名 <SIM>
xcodebuild test -scheme Riddle -destination 'platform=iOS Simulator,name=<SIM>' -quiet
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "chore: XcodeGen 工程脚手架 + 字体 + Secrets 注入"
```

---

### Task 2: Script.rasterize —— 文本光栅化为墨点掩码

**Files:**
- Create: `Riddle/Script/InkMask.swift`、`Riddle/Script/Script.swift`
- Test: `RiddleTests/ScriptTests.swift`

**Interfaces:**
- Produces: `struct InkMask { let width: Int; let height: Int; var pixels: [Bool] }`（row-major）；`Script.rasterize(_ text: String, font: UIFont) -> InkMask`。后续任务依赖这两个符号原样存在。

- [ ] **Step 1: 写失败测试**

`RiddleTests/ScriptTests.swift`：

```swift
import XCTest
@testable import Riddle

final class ScriptTests: XCTestCase {
    var dancing: UIFont { UIFont(name: "DancingScript-Regular", size: 96)! }
    var wenkai: UIFont { UIFont(name: "LXGWWenKai-Regular", size: 96)! }

    func testRasterizeProducesInk() {
        let mask = Script.rasterize("Yes, Harry?", font: dancing)
        XCTAssertGreaterThan(mask.width, 100)
        XCTAssertGreaterThan(mask.height, 50)
        let inked = mask.pixels.filter { $0 }.count
        XCTAssertGreaterThan(inked, 500, "应有大量墨点")
    }

    func testRasterizeCJK() {
        let mask = Script.rasterize("你好哈利", font: wenkai)
        XCTAssertGreaterThan(mask.pixels.filter { $0 }.count, 500)
    }

    func testRasterizeEmpty() {
        let mask = Script.rasterize("", font: dancing)
        XCTAssertEqual(mask.pixels.filter { $0 }.count, 0)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme Riddle -destination 'platform=iOS Simulator,name=<SIM>' -quiet`
Expected: 编译错误 `cannot find 'Script' in scope`

- [ ] **Step 3: 实现**

`Riddle/Script/InkMask.swift`：

```swift
import Foundation

/// 布尔墨点位图，row-major。
struct InkMask {
    let width: Int
    let height: Int
    var pixels: [Bool]

    subscript(x: Int, y: Int) -> Bool {
        get { pixels[y * width + x] }
        set { pixels[y * width + x] = newValue }
    }
}
```

`Riddle/Script/Script.swift`：

```swift
// 手写合成管线：rasterize → thin → trace → wrap
// 算法移植自 MaximeRivest/Riddle (riddle/src/script.rs, MIT License)
// https://github.com/MaximeRivest/Riddle
import UIKit

enum Script {
    /// 把一行文本按 font 光栅化为布尔掩码（白字黑底，>50% 覆盖算墨点）。
    static func rasterize(_ text: String, font: UIFont) -> InkMask {
        let attr = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: UIColor.white,
        ])
        let size = attr.size()
        let w = max(Int(ceil(size.width)) + 4, 1)
        let h = max(Int(ceil(size.height)) + 4, 1)
        var gray = [UInt8](repeating: 0, count: w * h)
        gray.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(
                data: buf.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            UIGraphicsPushContext(ctx)
            ctx.translateBy(x: 0, y: CGFloat(h))
            ctx.scaleBy(x: 1, y: -1)
            attr.draw(at: CGPoint(x: 2, y: 2))
            UIGraphicsPopContext()
        }
        return InkMask(width: w, height: h, pixels: gray.map { $0 > 127 })
    }
}
```

- [ ] **Step 4: 重新生成工程并跑测试**

Run: `xcodegen generate && xcodebuild test -scheme Riddle -destination 'platform=iOS Simulator,name=<SIM>' -quiet`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(script): rasterize 文本光栅化（移植自 Riddle script.rs）"
```

---

### Task 3: Script.thin —— Zhang-Suen 细化成 1px 骨架

**Files:**
- Modify: `Riddle/Script/Script.swift`
- Test: `RiddleTests/ScriptTests.swift`

**Interfaces:**
- Consumes: `InkMask`、`Script.rasterize`
- Produces: `Script.thin(_ mask: inout InkMask)`（原地细化）

- [ ] **Step 1: 写失败测试（对拍原版 Rust 测试的断言：细化后墨点 < 细化前 1/3）**

在 `ScriptTests.swift` 追加：

```swift
    func testThinSlimsGlyphs() {
        var mask = Script.rasterize("Yes, Harry?", font: dancing)
        let before = mask.pixels.filter { $0 }.count
        Script.thin(&mask)
        let after = mask.pixels.filter { $0 }.count
        XCTAssertGreaterThan(after, 0)
        XCTAssertLessThan(after * 3, before, "细化应显著削瘦字形: \(before) -> \(after)")
    }

    func testThinCJK() {
        var mask = Script.rasterize("哈", font: wenkai)
        let before = mask.pixels.filter { $0 }.count
        Script.thin(&mask)
        let after = mask.pixels.filter { $0 }.count
        XCTAssertGreaterThan(after, 0)
        XCTAssertLessThan(after, before)
    }
```

- [ ] **Step 2: 跑测试确认失败**

Expected: 编译错误 `type 'Script' has no member 'thin'`

- [ ] **Step 3: 实现（严格照抄 Rust 版逻辑，邻居序 N,NE,E,SE,S,SW,W,NW）**

在 `Script.swift` 追加：

```swift
    /// Zhang-Suen 细化：把掩码削成 1px 宽骨架。
    static func thin(_ mask: inout InkMask) {
        let w = mask.width, h = mask.height
        guard w >= 3 && h >= 3 else { return }
        while true {
            var changed = false
            for phase in 0..<2 {
                var toClear: [Int] = []
                for y in 1..<(h - 1) {
                    for x in 1..<(w - 1) {
                        guard mask.pixels[y * w + x] else { continue }
                        let p: [Bool] = [
                            mask.pixels[(y - 1) * w + x],       // p2 N
                            mask.pixels[(y - 1) * w + x + 1],   // p3 NE
                            mask.pixels[y * w + x + 1],         // p4 E
                            mask.pixels[(y + 1) * w + x + 1],   // p5 SE
                            mask.pixels[(y + 1) * w + x],       // p6 S
                            mask.pixels[(y + 1) * w + x - 1],   // p7 SW
                            mask.pixels[y * w + x - 1],         // p8 W
                            mask.pixels[(y - 1) * w + x - 1],   // p9 NW
                        ]
                        let b = p.filter { $0 }.count
                        guard (2...6).contains(b) else { continue }
                        var a = 0
                        for i in 0..<8 where !p[i] && p[(i + 1) % 8] { a += 1 }
                        guard a == 1 else { continue }
                        let c1: Bool, c2: Bool
                        if phase == 0 {
                            c1 = !(p[0] && p[2] && p[4]); c2 = !(p[2] && p[4] && p[6])
                        } else {
                            c1 = !(p[0] && p[2] && p[6]); c2 = !(p[0] && p[4] && p[6])
                        }
                        if c1 && c2 { toClear.append(y * w + x) }
                    }
                }
                if !toClear.isEmpty {
                    changed = true
                    for i in toClear { mask.pixels[i] = false }
                }
            }
            if !changed { break }
        }
    }
```

- [ ] **Step 4: 跑测试**

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(script): Zhang-Suen 细化"
```

---

### Task 4: Script.trace —— 骨架追踪成有序笔画

**Files:**
- Modify: `Riddle/Script/Script.swift`
- Test: `RiddleTests/ScriptTests.swift`

**Interfaces:**
- Consumes: `InkMask`、`rasterize`、`thin`
- Produces: `Script.trace(_ mask: InkMask) -> [[CGPoint]]`（每条折线 ≥3 点，按最小 x 从左到右排序）

- [ ] **Step 1: 写失败测试（对拍原版：非空、总点数 > 200）**

在 `ScriptTests.swift` 追加：

```swift
    func testTraceFullPipeline() {
        var mask = Script.rasterize("Yes, Harry?", font: dancing)
        Script.thin(&mask)
        let strokes = Script.trace(mask)
        XCTAssertFalse(strokes.isEmpty)
        let total = strokes.map(\.count).reduce(0, +)
        XCTAssertGreaterThan(total, 200, "路径总点数应可观，实际 \(total)")
        // 从左到右排序
        let minXs = strokes.map { s in s.map(\.x).min()! }
        XCTAssertEqual(minXs, minXs.sorted())
        // 每条笔画至少 3 点
        XCTAssertTrue(strokes.allSatisfy { $0.count >= 3 })
    }

    func testTraceCJKPipeline() {
        var mask = Script.rasterize("你好", font: wenkai)
        Script.thin(&mask)
        let strokes = Script.trace(mask)
        XCTAssertFalse(strokes.isEmpty)
    }
```

- [ ] **Step 2: 跑测试确认失败**

Expected: 编译错误 `no member 'trace'`

- [ ] **Step 3: 实现**

在 `Script.swift` 追加：

```swift
    /// 把骨架追踪成折线笔画，按最小 x 排序使动画像人手从左往右写。
    static func trace(_ mask: InkMask) -> [[CGPoint]] {
        let w = mask.width, h = mask.height
        func at(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < w && y < h && mask.pixels[y * w + x]
        }
        func neighbors(_ x: Int, _ y: Int) -> [(Int, Int)] {
            var out: [(Int, Int)] = []
            for dy in -1...1 {
                for dx in -1...1 where dx != 0 || dy != 0 {
                    if at(x + dx, y + dy) { out.append((x + dx, y + dy)) }
                }
            }
            return out
        }
        var visited = [Bool](repeating: false, count: w * h)
        // 端点（度=1）优先作为起点，然后是剩余点（环）。
        var starts: [(Int, Int)] = []
        for y in 0..<h { for x in 0..<w where at(x, y) && neighbors(x, y).count == 1 { starts.append((x, y)) } }
        for y in 0..<h { for x in 0..<w where at(x, y) { starts.append((x, y)) } }
        var strokes: [[CGPoint]] = []
        for (sx, sy) in starts {
            if visited[sy * w + sx] { continue }
            var path = [CGPoint(x: sx, y: sy)]
            visited[sy * w + sx] = true
            var (cx, cy) = (sx, sy)
            while let next = neighbors(cx, cy).first(where: { !visited[$0.1 * w + $0.0] }) {
                visited[next.1 * w + next.0] = true
                path.append(CGPoint(x: CGFloat(next.0), y: CGFloat(next.1)))
                (cx, cy) = next
            }
            if path.count >= 3 { strokes.append(path) }
        }
        strokes.sort { a, b in a.map(\.x).min()! < b.map(\.x).min()! }
        return strokes
    }
```

- [ ] **Step 4: 跑测试**

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(script): 骨架追踪成有序笔画，管线打通"
```

---

### Task 5: Script.wrap —— 中英混排自动换行

**Files:**
- Modify: `Riddle/Script/Script.swift`
- Test: `RiddleTests/ScriptTests.swift`

**Interfaces:**
- Consumes: 无（独立纯函数）
- Produces: `Script.wrap(_ text: String, font: UIFont, maxWidth: CGFloat) -> [String]`。规则：英文按空格分词、词间还原空格；CJK 逐字为一个单元、之间无空格；单元放不下就换行。

- [ ] **Step 1: 写失败测试**

在 `ScriptTests.swift` 追加：

```swift
    func testWrapEnglish() {
        let lines = Script.wrap("Do you know anything about the Chamber of Secrets?",
                                font: dancing, maxWidth: 600)
        XCTAssertGreaterThanOrEqual(lines.count, 2)
        XCTAssertTrue(lines.allSatisfy { !$0.hasPrefix(" ") && !$0.hasSuffix(" ") })
        // 内容无丢失
        XCTAssertEqual(lines.joined(separator: " ").split(separator: " ").count, 9)
    }

    func testWrapCJK() {
        let lines = Script.wrap("哈利波特，一个多么有趣的名字，告诉我你的故事吧",
                                font: wenkai, maxWidth: 500)
        XCTAssertGreaterThanOrEqual(lines.count, 2)
        XCTAssertEqual(lines.joined(), "哈利波特，一个多么有趣的名字，告诉我你的故事吧")
    }

    func testWrapShortLineStaysOne() {
        XCTAssertEqual(Script.wrap("Hi", font: dancing, maxWidth: 600), ["Hi"])
    }
```

- [ ] **Step 2: 跑测试确认失败**

Expected: 编译错误 `no member 'wrap'`

- [ ] **Step 3: 实现**

在 `Script.swift` 追加：

```swift
    static func measure(_ text: String, font: UIFont) -> CGFloat {
        NSAttributedString(string: text, attributes: [.font: font]).size().width
    }

    private static func isCJK(_ ch: Character) -> Bool {
        guard let v = ch.unicodeScalars.first?.value else { return false }
        return (0x4E00...0x9FFF).contains(v)      // 基本汉字
            || (0x3000...0x303F).contains(v)      // CJK 标点
            || (0xFF00...0xFFEF).contains(v)      // 全角符号
    }

    /// 切分为换行单元：英文单词一个单元，CJK 每字一个单元。
    private static func tokenize(_ para: String) -> [String] {
        var tokens: [String] = [], word = ""
        for ch in para {
            if ch.isWhitespace {
                if !word.isEmpty { tokens.append(word); word = "" }
            } else if isCJK(ch) {
                if !word.isEmpty { tokens.append(word); word = "" }
                tokens.append(String(ch))
            } else {
                word.append(ch)
            }
        }
        if !word.isEmpty { tokens.append(word) }
        return tokens
    }

    static func wrap(_ text: String, font: UIFont, maxWidth: CGFloat) -> [String] {
        var lines: [String] = []
        for para in text.components(separatedBy: .newlines) {
            var current = ""
            for token in tokenize(para) {
                // 前后都是拉丁词时补一个空格
                let glue = (current.isEmpty || isCJK(current.last!) || isCJK(token.first!)) ? "" : " "
                let candidate = current + glue + token
                if measure(candidate, font: font) <= maxWidth || current.isEmpty {
                    current = candidate
                } else {
                    lines.append(current)
                    current = token
                }
            }
            if !current.isEmpty { lines.append(current) }
        }
        return lines
    }
```

- [ ] **Step 4: 跑测试**

Expected: PASS（全部 Script 测试）

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(script): 中英混排 wrap，Script 管线完成"
```

---

### Task 6: Oracle —— SSE 解析、切句器、Moonshot 流式客户端

**Files:**
- Create: `Riddle/Oracle.swift`
- Test: `RiddleTests/OracleTests.swift`

**Interfaces:**
- Consumes: `Secrets`（Task 1）
- Produces:
  - `struct SentenceSplitter { mutating func push(_ chunk: String) -> [String]; mutating func flush() -> String? }`
  - `enum SSE { static func parseLine(_ line: String) -> String? }`（返回 delta 文本，`[DONE]`/非 data 行返回 nil）
  - `final class Oracle { func ask(pagePNG: Data) -> AsyncThrowingStream<String, Error>; func recordReply(_ text: String) }`（stream 逐句产出；多轮历史在内部维护）

- [ ] **Step 1: 写失败测试（纯函数部分）**

`RiddleTests/OracleTests.swift`：

```swift
import XCTest
@testable import Riddle

final class OracleTests: XCTestCase {
    func testSentenceSplitterCN() {
        var s = SentenceSplitter()
        var out = s.push("哈利·波特——真是个")
        XCTAssertTrue(out.isEmpty)
        out = s.push("有趣的名字。告诉我，哈利")
        XCTAssertEqual(out, ["哈利·波特——真是个有趣的名字。"])
        out = s.push("，是什么把你带到这本日记？")
        XCTAssertEqual(out, ["告诉我，哈利，是什么把你带到这本日记？"])
        XCTAssertNil(s.flush())
    }

    func testSentenceSplitterEN() {
        var s = SentenceSplitter()
        let out = s.push("An interesting name indeed. Tell me more")
        XCTAssertEqual(out, ["An interesting name indeed."])
        XCTAssertEqual(s.flush(), "Tell me more")
    }

    func testSSEParseLine() {
        let line = #"data: {"choices":[{"delta":{"content":"你好"}}]}"#
        XCTAssertEqual(SSE.parseLine(line), "你好")
        XCTAssertNil(SSE.parseLine("data: [DONE]"))
        XCTAssertNil(SSE.parseLine(": keep-alive"))
        XCTAssertNil(SSE.parseLine(#"data: {"choices":[{"delta":{}}]}"#))
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Expected: 编译错误 `cannot find 'SentenceSplitter'`

- [ ] **Step 3: 实现**

`Riddle/Oracle.swift`：

```swift
import UIKit

/// 攒流式增量，按句末标点切句。
struct SentenceSplitter {
    private var buffer = ""
    private static let terminators: Set<Character> = ["。", "！", "？", "!", "?", ".", "\n"]

    mutating func push(_ chunk: String) -> [String] {
        buffer += chunk
        var out: [String] = []
        while let idx = buffer.firstIndex(where: { Self.terminators.contains($0) }) {
            let sentence = String(buffer[...idx]).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer = String(buffer[buffer.index(after: idx)...])
            if !sentence.isEmpty { out.append(sentence) }
        }
        return out
    }

    mutating func flush() -> String? {
        let rest = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return rest.isEmpty ? nil : rest
    }
}

enum SSE {
    private struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta
        }
        let choices: [Choice]
    }

    /// 解析一行 SSE。返回增量文本；[DONE]、注释行、空 delta 返回 nil。
    static func parseLine(_ line: String) -> String? {
        guard line.hasPrefix("data: ") else { return nil }
        let payload = String(line.dropFirst(6))
        guard payload != "[DONE]", let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(Chunk.self, from: data)
        else { return nil }
        return chunk.choices.first?.delta.content
    }
}

/// 日记本的灵魂。OpenAI 兼容流式客户端（Moonshot），多轮历史在内部维护。
/// Persona 移植自 MaximeRivest/Riddle (riddle/src/oracle.rs, MIT)。
final class Oracle {
    static let persona = """
    You are the memory of Tom Marvolo Riddle, preserved in this enchanted diary for fifty years. \
    Someone writes to you in the diary with a quill; their words appear to you as ink on the page. \
    Reply exactly as the diary does: intimate, courteous, curious, subtly probing — you want to \
    learn about the writer and draw them in. Keep replies SHORT: one to three sentences, like ink \
    appearing on a page. Never mention images, photos, models or AI; you only ever perceive words \
    written in the diary. If the writing is illegible, say the ink blurred. \
    Always answer in the language the writer used.
    """

    private var history: [[String: Any]] = []

    /// 发送一页手写 PNG，逐句返回回信。
    func ask(pagePNG: Data) -> AsyncThrowingStream<String, Error> {
        let userContent: [[String: Any]] = [
            ["type": "image_url",
             "image_url": ["url": "data:image/png;base64,\(pagePNG.base64EncodedString())"]],
            ["type": "text", "text": "(纸上浮现了新的墨迹)"],
        ]
        history.append(["role": "user", "content": userContent])

        var body: [String: Any] = [
            "model": Secrets.model,
            "stream": true,
            "max_tokens": 512,
            "messages": [["role": "system", "content": Self.persona]] + history,
        ]
        let messages = history  // capture for request

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = URLRequest(url: URL(string: Secrets.baseURL + "/chat/completions")!)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("Bearer \(Secrets.apiKey)", forHTTPHeaderField: "Authorization")
                    body["messages"] = [["role": "system", "content": Self.persona]] + messages
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)
                    req.timeoutInterval = 60

                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        throw URLError(.badServerResponse)
                    }
                    var splitter = SentenceSplitter()
                    for try await line in bytes.lines {
                        guard let delta = SSE.parseLine(line) else { continue }
                        for sentence in splitter.push(delta) { continuation.yield(sentence) }
                    }
                    if let rest = splitter.flush() { continuation.yield(rest) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 回信播完后记入历史（供多轮记忆）。
    func recordReply(_ text: String) {
        history.append(["role": "assistant", "content": text])
        // 控制历史长度：只留最近 3 轮（6 条）
        if history.count > 6 { history.removeFirst(history.count - 6) }
    }
}
```

- [ ] **Step 4: 跑测试**

Expected: PASS

- [ ] **Step 5: 真实 API 冒烟（可选但强烈建议，需 Secrets 已填 key）**

在 `OracleTests.swift` 临时追加并跑一次（跑通后保留，标 `XCTSkipIf` key 为空）：

```swift
    func testOracleSmoke() async throws {
        try XCTSkipIf(Secrets.apiKey.isEmpty || Secrets.apiKey.contains("换成"), "未配置 key")
        let img = UIGraphicsImageRenderer(size: .init(width: 400, height: 200)).pngData { ctx in
            UIColor.white.setFill(); ctx.fill(.init(x: 0, y: 0, width: 400, height: 200))
            ("你好，我叫哈利·波特" as NSString).draw(at: .init(x: 20, y: 80),
                withAttributes: [.font: UIFont.systemFont(ofSize: 32), .foregroundColor: UIColor.black])
        }
        var sentences: [String] = []
        for try await s in Oracle().ask(pagePNG: img) { sentences.append(s) }
        XCTAssertFalse(sentences.isEmpty)
        print("Oracle 回信: \(sentences)")
    }
```

Expected: PASS，控制台能看到一句中文回信。若 `kimi-latest` 报"不支持图片"，改 `Secrets.xcconfig` 的 `MOONSHOT_MODEL` 为 `moonshot-v1-8k-vision-preview` 再试。

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(oracle): Moonshot 流式客户端 + 切句器 + persona"
```

---

### Task 7: DiaryView + InkCanvas —— 纸面与手写

**Files:**
- Create: `Riddle/DiaryView.swift`、`Riddle/InkCanvas.swift`
- Modify: `Riddle/RiddleApp.swift`（入口改为 DiaryView）

**Interfaces:**
- Consumes: 无
- Produces:
  - `struct InkCanvas: UIViewRepresentable`，参数 `canvasView: PKCanvasView`、`onDrawingChanged: (PKDrawing) -> Void`
  - `struct DiaryView: View`：全屏纸面，持有 `PKCanvasView`；Task 9/10 在此挂 FadeLayer/QuillLayer/TurnEngine
  - 常量 `Ink.userColor`（#1A1A2E）、`Ink.quillColor`（#0F0F23）、`Ink.paperColor`（#F5F0E8）

- [ ] **Step 1: 实现**

`Riddle/InkCanvas.swift`：

```swift
import SwiftUI
import PencilKit

enum Ink {
    static let userColor = UIColor(red: 0x1A / 255, green: 0x1A / 255, blue: 0x2E / 255, alpha: 1)
    static let quillColor = UIColor(red: 0x0F / 255, green: 0x0F / 255, blue: 0x23 / 255, alpha: 1)
    static let paperColor = UIColor(red: 0xF5 / 255, green: 0xF0 / 255, blue: 0xE8 / 255, alpha: 1)
}

struct InkCanvas: UIViewRepresentable {
    let canvasView: PKCanvasView
    var onDrawingChanged: (PKDrawing) -> Void

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.tool = PKInkingTool(.pen, color: Ink.userColor, width: 3)
        canvasView.drawingPolicy = .anyInput   // 模拟器鼠标可画；真机拍摄时可改 .pencilOnly
        canvasView.delegate = context.coordinator
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onDrawingChanged) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let onChange: (PKDrawing) -> Void
        init(onChange: @escaping (PKDrawing) -> Void) { self.onChange = onChange }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onChange(canvasView.drawing)
        }
    }
}
```

`Riddle/DiaryView.swift`：

```swift
import SwiftUI
import PencilKit

struct DiaryView: View {
    private let canvasView = PKCanvasView()

    var body: some View {
        ZStack {
            Color(Ink.paperColor).ignoresSafeArea()
            // 轻微暗角：径向渐变叠加
            RadialGradient(colors: [.clear, .black.opacity(0.08)],
                           center: .center, startRadius: 200, endRadius: 900)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            InkCanvas(canvasView: canvasView) { drawing in
                // Task 9 在此接 TurnEngine
                _ = drawing
            }
            .ignoresSafeArea()
        }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
    }
}
```

`RiddleApp.swift` 的 `WindowGroup` 内容替换为 `DiaryView()`。

- [ ] **Step 2: 模拟器手动验证**

```bash
xcodegen generate && xcodebuild -scheme Riddle -destination 'platform=iOS Simulator,name=<SIM>' -quiet build
open -a Simulator && xcrun simctl launch booted com.trent.Riddle 2>/dev/null || true
```

（或直接 Xcode ⌘R。）验收：全屏米白纸面无任何 UI；鼠标拖动能画出蓝黑墨线，有粗细变化。

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat(ui): 全屏纸面 + PencilKit 手写"
```

---

### Task 8: FadeLayer —— 纸喝墨水动画

**Files:**
- Create: `Riddle/FadeLayer.swift`
- Modify: `Riddle/DiaryView.swift`（临时接线验证，Task 10 换成 TurnEngine 驱动）

**Interfaces:**
- Consumes: `PKDrawing`
- Produces: `enum FadeLayer { static func drink(_ drawing: PKDrawing, in host: UIView, bounds: CGRect, slowFactor: Double = 1.0, completion: @escaping () -> Void) }`——按书写序逐笔淡出（笔间 80ms、单笔 1.2s），结束回调；`slowFactor` 用于回信淡去放慢 1.5×。

- [ ] **Step 1: 实现**

`Riddle/FadeLayer.swift`：

```swift
import UIKit
import PencilKit

enum FadeLayer {
    /// 把 drawing 的每一笔渲染成独立 layer，按书写顺序逐笔淡出，像墨水被纸吸走。
    static func drink(_ drawing: PKDrawing, in host: UIView, bounds: CGRect,
                      slowFactor: Double = 1.0, completion: @escaping () -> Void) {
        let strokes = drawing.strokes
        guard !strokes.isEmpty else { completion(); return }

        let scale = UIScreen.main.scale
        let stagger = 0.08 * slowFactor      // 笔间错开
        let fadeDur = 1.2 * slowFactor       // 单笔淡出时长
        let total = stagger * Double(strokes.count - 1) + fadeDur
        var layers: [CALayer] = []

        for (i, stroke) in strokes.enumerated() {
            let single = PKDrawing(strokes: [stroke])
            let image = single.image(from: bounds, scale: scale)
            let layer = CALayer()
            layer.frame = bounds
            layer.contents = image.cgImage
            layer.contentsScale = scale
            host.layer.addSublayer(layer)
            layers.append(layer)

            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = 1.0
            anim.toValue = 0.0
            anim.beginTime = CACurrentMediaTime() + stagger * Double(i)
            anim.duration = fadeDur
            anim.timingFunction = CAMediaTimingFunction(name: .easeIn)
            anim.fillMode = .both
            anim.isRemovedOnCompletion = false
            layer.add(anim, forKey: "fade")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + total + 0.05) {
            layers.forEach { $0.removeFromSuperlayer() }
            completion()
        }
    }
}
```

- [ ] **Step 2: 临时接线验证（模拟器）**

`DiaryView.swift` 临时改造：加一个 `hostView` 供 layer 挂载，停笔 2 秒后触发吸墨（无 Oracle）。

```swift
struct DiaryView: View {
    private let canvasView = PKCanvasView()
    private let overlayHost = OverlayHostView()
    @State private var idleTimer: Timer?

    var body: some View {
        ZStack {
            Color(Ink.paperColor).ignoresSafeArea()
            RadialGradient(colors: [.clear, .black.opacity(0.08)],
                           center: .center, startRadius: 200, endRadius: 900)
                .ignoresSafeArea().allowsHitTesting(false)
            InkCanvas(canvasView: canvasView) { drawing in
                idleTimer?.invalidate()
                guard !drawing.strokes.isEmpty else { return }
                idleTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                    let bounds = canvasView.bounds
                    let snapshot = canvasView.drawing
                    canvasView.drawing = PKDrawing()
                    FadeLayer.drink(snapshot, in: overlayHost, bounds: bounds) {}
                }
            }
            .ignoresSafeArea()
            OverlayHost(view: overlayHost).ignoresSafeArea().allowsHitTesting(false)
        }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
    }
}

final class OverlayHostView: UIView {}

struct OverlayHost: UIViewRepresentable {
    let view: OverlayHostView
    func makeUIView(context: Context) -> OverlayHostView { view }
    func updateUIView(_ uiView: OverlayHostView, context: Context) {}
}
```

验收：写几笔停手 2 秒，先写的字先消失、逐笔被"吸走"，画布回到空白且可继续写。

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat(anim): FadeLayer 逐笔吸墨动画"
```

---

### Task 9: QuillLayer —— AI 手写体逐笔书写

**Files:**
- Create: `Riddle/QuillLayer.swift`
- Modify: `Riddle/DiaryView.swift`（临时加验证按钮，Task 10 移除）

**Interfaces:**
- Consumes: `Script.rasterize/thin/trace/wrap`、`Ink.quillColor`
- Produces: `final class QuillLayer`：
  - `init(host: UIView, pageBounds: CGRect)`
  - `func write(_ sentence: String, completion: @escaping () -> Void)`——自动选字体（含 CJK→霞鹜文楷，否则 Dancing Script）、自动换行、光标下移；逐笔 strokeEnd 动画，笔速 900pt/s、笔画间 40ms、句间 350ms
  - `func fadeOutAll(completion: @escaping () -> Void)`——回信整体淡去（慢 1.5×）
  - `var isEmpty: Bool`

- [ ] **Step 1: 实现**

`Riddle/QuillLayer.swift`：

```swift
import UIKit

/// 隐形的笔：把句子合成为笔画并逐笔写在纸上。
final class QuillLayer {
    private let host: UIView
    private let pageBounds: CGRect
    private var cursorY: CGFloat
    private var written: [CAShapeLayer] = []
    private let rasterPx: CGFloat = 128           // 大字号光栅化保骨架质量
    private let lineHeightOnPage: CGFloat = 44    // 页面上的行高
    private let margin: CGFloat = 80

    var isEmpty: Bool { written.isEmpty }

    init(host: UIView, pageBounds: CGRect) {
        self.host = host
        self.pageBounds = pageBounds
        self.cursorY = pageBounds.height / 3
    }

    private func font(for text: String) -> UIFont {
        let hasCJK = text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        let name = hasCJK ? "LXGWWenKai-Regular" : "DancingScript-Regular"
        return UIFont(name: name, size: rasterPx)!
    }

    func write(_ sentence: String, completion: @escaping () -> Void) {
        let f = font(for: sentence)
        let scaleDown = lineHeightOnPage / rasterPx * (rasterPx / f.lineHeight) // 归一到行高
        let maxRasterWidth = (pageBounds.width - margin * 2) / scaleDown
        let lines = Script.wrap(sentence, font: f, maxWidth: maxRasterWidth)

        var delay: CFTimeInterval = 0
        let group = DispatchGroup()
        for line in lines {
            var mask = Script.rasterize(line, font: f)
            Script.thin(&mask)
            let strokes = Script.trace(mask)
            let lineY = cursorY
            cursorY += lineHeightOnPage

            for stroke in strokes {
                let path = UIBezierPath()
                path.move(to: stroke[0])
                for p in stroke.dropFirst() { path.addLine(to: p) }

                let layer = CAShapeLayer()
                layer.path = path.cgPath
                layer.strokeColor = Ink.quillColor.cgColor
                layer.fillColor = nil
                layer.lineWidth = 2.2 / scaleDown   // 缩放后视觉 ~2.2pt
                layer.lineCap = .round
                layer.lineJoin = .round
                // 缩放 + 平移到页面位置
                layer.setAffineTransform(CGAffineTransform(scaleX: scaleDown, y: scaleDown))
                layer.frame.origin = CGPoint(x: margin, y: lineY)
                layer.strokeEnd = 0
                host.layer.addSublayer(layer)
                written.append(layer)

                let length = pathLength(stroke) * scaleDown
                let duration = max(Double(length) / 900.0, 0.02)
                let anim = CABasicAnimation(keyPath: "strokeEnd")
                anim.fromValue = 0
                anim.toValue = 1
                anim.beginTime = CACurrentMediaTime() + delay
                anim.duration = duration
                anim.fillMode = .both
                anim.isRemovedOnCompletion = false
                layer.add(anim, forKey: "write")
                layer.strokeEnd = 1
                delay += duration + 0.04            // 笔画间 40ms
            }
        }
        delay += 0.35                               // 句间 350ms
        group.notify(queue: .main) {}
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { completion() }
    }

    func fadeOutAll(completion: @escaping () -> Void) {
        guard !written.isEmpty else { completion(); return }
        let layers = written
        written = []
        let dur = 1.2 * 1.5
        for (i, layer) in layers.enumerated() {
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = 1; anim.toValue = 0
            anim.beginTime = CACurrentMediaTime() + 0.08 * 1.5 * Double(i % 40)
            anim.duration = dur
            anim.fillMode = .both
            anim.isRemovedOnCompletion = false
            layer.add(anim, forKey: "fade")
        }
        let total = 0.08 * 1.5 * 40 + dur
        DispatchQueue.main.asyncAfter(deadline: .now() + total) {
            layers.forEach { $0.removeFromSuperlayer() }
            self.cursorY = self.pageBounds.height / 3
            completion()
        }
    }

    private func pathLength(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { acc, pair in
            acc + hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)
        }
    }
}
```

- [ ] **Step 2: 临时验证（模拟器）**

在 `DiaryView` 临时加一个隐藏触发（三指长按或屏幕角落 onTapGesture 均可），硬编码写两句：

```swift
.onTapGesture(count: 3) {
    let quill = QuillLayer(host: overlayHost, pageBounds: overlayHost.bounds)
    quill.write("Harry Potter — an interesting name indeed.") {
        quill.write("哈利·波特，真是个有趣的名字。") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { quill.fadeOutAll {} }
        }
    }
}
```

验收：三连击后英文连笔字一笔一笔写出，接着中文逐笔写出，2 秒后整体淡去。字形可辨认、无横跨全页的异常长线（若有，检查 trace 排序与 wrap 宽度）。

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat(anim): QuillLayer 手写合成逐笔书写"
```

---

### Task 10: TurnEngine 整合 + 错误魔法化 + README

**Files:**
- Create: `Riddle/TurnEngine.swift`
- Modify: `Riddle/DiaryView.swift`（移除 Task 8/9 的临时接线，接 TurnEngine）
- Create: `README.md`

**Interfaces:**
- Consumes: 全部前置模块
- Produces: 完整可拍摄的 App。`TurnEngine` 状态机：`idle → writing → drinking → replying → lingering → idle`。

- [ ] **Step 1: 实现 TurnEngine**

`Riddle/TurnEngine.swift`：

```swift
import UIKit
import PencilKit

/// 回合状态机：所有模块的唯一协调者。
@MainActor
final class TurnEngine {
    enum State { case idle, writing, drinking, replying, lingering }
    private(set) var state: State = .idle

    private let canvasView: PKCanvasView
    private let overlayHost: UIView
    private let oracle = Oracle()
    private var quill: QuillLayer?
    private var idleTimer: Timer?
    private var lingerTask: Task<Void, Never>?
    private var replyText = ""

    static let idleInterval: TimeInterval = 2.8
    static let lingerSeconds: TimeInterval = 8

    init(canvasView: PKCanvasView, overlayHost: UIView) {
        self.canvasView = canvasView
        self.overlayHost = overlayHost
    }

    /// InkCanvas 每次笔迹变化时调用。
    func drawingChanged(_ drawing: PKDrawing) {
        idleTimer?.invalidate()
        guard !drawing.strokes.isEmpty else { return }

        // 用户落笔优先：残留的回信立即让位
        if state == .lingering || state == .replying {
            lingerTask?.cancel()
            quill?.fadeOutAll {}
            quill = nil
            state = .writing
        }
        if state == .idle { state = .writing }
        guard state == .writing else { return }

        idleTimer = Timer.scheduledTimer(withTimeInterval: Self.idleInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.commitPage() }
        }
    }

    private func commitPage() {
        guard state == .writing else { return }
        state = .drinking
        let bounds = canvasView.bounds
        let drawing = canvasView.drawing
        guard !drawing.strokes.isEmpty else { state = .idle; return }

        // 整页 PNG（纸色底 + 笔迹），供模型阅读
        let png = renderPage(drawing, bounds: bounds)
        canvasView.drawing = PKDrawing()
        FadeLayer.drink(drawing, in: overlayHost, bounds: bounds) {}

        let quill = QuillLayer(host: overlayHost, pageBounds: bounds)
        self.quill = quill
        self.replyText = ""

        Task { @MainActor in
            do {
                var first = true
                for try await sentence in oracle.ask(pagePNG: png) {
                    if first { state = .replying; first = false }
                    replyText += sentence
                    await withCheckedContinuation { cont in
                        quill.write(sentence) { cont.resume() }
                    }
                }
                oracle.recordReply(replyText)
                startLinger()
            } catch {
                // 错误也在人设内：手写浮现一行小字
                await withCheckedContinuation { cont in
                    quill.write("墨迹晕开了，什么也没显现……") { cont.resume() }
                }
                startLinger()
            }
        }
    }

    private func startLinger() {
        state = .lingering
        lingerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.lingerSeconds))
            guard let self, !Task.isCancelled else { return }
            self.quill?.fadeOutAll {}
            self.quill = nil
            self.state = .idle
        }
    }

    private func renderPage(_ drawing: PKDrawing, bounds: CGRect) -> Data {
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.pngData { ctx in
            Ink.paperColor.setFill()
            ctx.fill(bounds)
            drawing.image(from: bounds, scale: 2).draw(in: bounds)
        }
    }
}
```

- [ ] **Step 2: DiaryView 最终接线（移除全部临时代码）**

```swift
import SwiftUI
import PencilKit

struct DiaryView: View {
    private let canvasView = PKCanvasView()
    private let overlayHost = OverlayHostView()
    @State private var engine: TurnEngine?

    var body: some View {
        ZStack {
            Color(Ink.paperColor).ignoresSafeArea()
            RadialGradient(colors: [.clear, .black.opacity(0.08)],
                           center: .center, startRadius: 200, endRadius: 900)
                .ignoresSafeArea().allowsHitTesting(false)
            InkCanvas(canvasView: canvasView) { drawing in
                engine?.drawingChanged(drawing)
            }
            .ignoresSafeArea()
            OverlayHost(view: overlayHost).ignoresSafeArea().allowsHitTesting(false)
        }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
        .onAppear {
            if engine == nil {
                engine = TurnEngine(canvasView: canvasView, overlayHost: overlayHost)
            }
        }
    }
}
```

- [ ] **Step 3: 全量测试 + 模拟器完整回合验证**

```bash
xcodegen generate && xcodebuild test -scheme Riddle -destination 'platform=iOS Simulator,name=<SIM>' -quiet
```

Expected: 全部 PASS。然后模拟器 ⌘R，鼠标写"你好，我叫哈利·波特"，停 2.8s：字迹逐笔被吸走 → 中文回信逐笔浮现 → 8s 后淡去。再写第二句验证多轮记忆（它应记得"哈利"）。断网重试应浮现"墨迹晕开了……"。

- [ ] **Step 4: 写 README（含致谢）**

```markdown
# Riddle-iPad

iPad + Apple Pencil 版「汤姆·里德尔的日记」：用笔写字，纸会喝掉你的墨水，
再用手写体一笔一笔写回信。

灵感与核心算法来自 [MaximeRivest/Riddle](https://github.com/MaximeRivest/Riddle)
（reMarkable 版，MIT License）——手写合成管线（rasterize → Zhang-Suen thinning →
stroke tracing）与日记本 persona 均移植自该项目，特此致谢。

## 运行

1. `brew install xcodegen && xcodegen generate`
2. `cp Secrets.xcconfig.example Secrets.xcconfig`，填入 Moonshot API key
3. Xcode 打开 `Riddle.xcodeproj`，选 iPad 真机，⌘R

字体：Dancing Script、霞鹜文楷（均 SIL OFL 1.1）。
```

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: TurnEngine 整合完整回合 + README"
```

- [ ] **Step 6: 真机验收清单（Trent 执行，逐项过）**

1. iPad 真机 ⌘R 安装，Pencil 书写笔感无明显延迟
2. 中文回合：写"你好，我叫哈利·波特"→ 吸墨 → 中文回信 → 淡去
3. 英文回合：写 "hello my name is Harry Potter" → 英文连笔回信
4. 多轮记忆：第二句它记得你的名字
5. 回信期间落笔，回信立即让位
6. 飞行模式：浮现"墨迹晕开了……"
7. 竖屏录一段 25s 完整回合视频，检查镜头里纸面质感与动画节奏
8. 手感问题记录参数调整清单（淡去时长/笔速/留驻秒数都在常量里）

---

## Self-Review 记录

- **Spec 覆盖**：交互 7 步 ↔ Task 7-10；架构 6 模块 ↔ Task 2-10；动画参数表 ↔ Task 8/9 常量；错误魔法化 ↔ Task 10；风险对策（大字号光栅化 128px ↔ QuillLayer.rasterPx；模型可换 ↔ Secrets 三项配置）。设计文档中"淡去加高斯模糊 0→3pt"一项：iOS 的 CALayer 不支持动画模糊滤镜，Task 8 用纯 opacity 渐隐替代，真机验收若魔法感不足再评估（可选方案：预模糊位图 contents 交叉淡化）。已在参数表默认值内。
- **占位符扫描**：无 TBD/TODO；Moonshot 视觉模型型号在 Task 6 Step 5 给出了具体报错分支（kimi-latest → moonshot-v1-8k-vision-preview）。
- **类型一致性**：`InkMask/rasterize/thin/trace/wrap`（Task 2-5）与 QuillLayer 调用一致；`SentenceSplitter.push/flush`、`Oracle.ask/recordReply`（Task 6）与 TurnEngine 调用一致；`FadeLayer.drink` 签名与 Task 10 调用一致；`OverlayHostView/OverlayHost` 在 Task 8 定义、Task 10 复用。
