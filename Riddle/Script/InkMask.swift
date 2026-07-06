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
