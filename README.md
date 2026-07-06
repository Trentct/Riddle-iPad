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
