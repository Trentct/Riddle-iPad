# Riddle-iPad

Tom Riddle's diary, for iPad + Apple Pencil: write on the page with your pencil, the paper **drinks your ink**, and an answer writes itself back in a flowing hand, stroke by stroke — then fades away.

No chat UI, no buttons, no keyboard. Just ink appearing on paper.

An iPad-native port of [MaximeRivest/Riddle](https://github.com/MaximeRivest/Riddle) (the reMarkable version, MIT). The handwriting-synthesis pipeline and the diary persona are ported from that project — all credit for the original magic goes there.

## How it works

```
pencil strokes (PencilKit)
  │ rest the pen 2.8s → page rendered to PNG
  ▼
vision LLM (OpenAI-compatible, streams sentence by sentence)
  │ each sentence: rasterize (any TTF) → Zhang-Suen thinning
  │ → skeleton tracing → single-pixel pen paths
  ▼
CAShapeLayer strokeEnd replay (~900 pt/s, like an invisible quill)
```

The synthesis pipeline is font-agnostic: English replies come out in cursive (Dancing Script), Chinese in a handwritten kai (LXGW WenKai) — same code path, no per-glyph stroke data needed. The diary always answers in whatever language you wrote in.

## Run it

You need: a Mac with Xcode, an iPad (iPadOS 17+) with Apple Pencil, and an API key for any OpenAI-compatible **vision** model (Moonshot by default).

```sh
brew install xcodegen
xcodegen generate
cp Secrets.xcconfig.example Secrets.xcconfig   # then put your API key in it
```

Open `Riddle.xcodeproj`, select your iPad, ⌘R. Write to the diary, and rest your pen.

To use a different provider, edit `MOONSHOT_BASE_URL` / `MOONSHOT_MODEL` in `Secrets.xcconfig` — anything that speaks `/chat/completions` with image input works.

## Credits & License

- Algorithm & persona: [MaximeRivest/Riddle](https://github.com/MaximeRivest/Riddle) (MIT)
- Fonts: [Dancing Script](https://github.com/googlefonts/DancingScript), [LXGW WenKai](https://github.com/lxgw/LxgwWenKai) (both SIL OFL 1.1)
- This repository: MIT (see LICENSE)

---

## 中文说明

iPad + Apple Pencil 版「汤姆·里德尔的日记」：用笔写字，纸会喝掉你的墨水，再用手写体一笔一笔写回信，随后淡去。

灵感与核心算法来自 [MaximeRivest/Riddle](https://github.com/MaximeRivest/Riddle)（reMarkable 版，MIT）——手写合成管线（光栅化 → Zhang-Suen 细化 → 骨架追踪）与日记本 persona 均移植自该项目，特此致谢。

**运行**：装 XcodeGen 并 `xcodegen generate`；复制 `Secrets.xcconfig.example` 为 `Secrets.xcconfig` 填入 API key（默认 Moonshot，任何 OpenAI 兼容视觉模型都可，改 base_url/model 即可）；Xcode 打开工程选 iPad 真机 ⌘R。

> MVP 注：设计稿中的「吸墨高斯模糊」与「纸面纹理贴图」在 iOS CALayer 动画限制与拍摄效果评估后裁剪，纯 opacity 渐隐 + 纯色纸面已满足镜头表现。

产品与技术细节见 `docs/产品文档.md`。
