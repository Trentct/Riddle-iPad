import Foundation

/// Holds loaded SDT handwriting trajectory banks, keyed by style name. Parallel to
/// ReplyHandStore: a single @MainActor singleton shared by QuillLayer and HandPickerView.
/// Loading is lazy and cached per style — a failed load (missing/malformed bundle files)
/// caches `nil` so every caller falls back to the font pipeline consistently instead of
/// retrying the (potentially expensive) decode on every access.
@MainActor
final class HandBankStore {
    static let shared = HandBankStore()

    private var cache: [String: HandBank?] = [:]

    private init() {}

    /// Returns the bank for `style`, loading (and caching, success or failure) on first
    /// access. Returns nil if the style has never loaded successfully.
    func bank(for style: String) -> HandBank? {
        if let cached = cache[style] { return cached }
        let loaded = HandBank.load(style: style)
        cache[style] = loaded
        return loaded
    }

    /// Preloads `style` eagerly (e.g. at app launch) so the first real use isn't blocked
    /// on the gunzip + JSON decode. Safe to call more than once — later calls are no-ops
    /// once cached.
    func preload(style: String) {
        _ = bank(for: style)
    }
}
