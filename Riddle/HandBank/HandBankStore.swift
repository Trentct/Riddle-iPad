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
    /// once cached. Synchronous — runs the decode on whatever thread/actor calls it. Kept
    /// for callers (e.g. tests) that want an immediate, fully-loaded bank; app launch uses
    /// `preloadAsync(style:)` instead so the decode doesn't block the main thread.
    func preload(style: String) {
        _ = bank(for: style)
    }

    /// Async counterpart to `preload(style:)`, meant for cold-launch use: the heavy gunzip +
    /// JSON decode (two inflates, ~2.7MB decompressed, 13,526 records) runs off the main actor
    /// — inside a nested `Task.detached` calling the `nonisolated` `loadBank(style:)` — so
    /// launch's first frame isn't blocked. Only once that off-actor work finishes does this
    /// function (itself @MainActor, like the rest of this store) resume and write the result
    /// into `cache`, so `cache` is never mutated off the main actor. Safe to call more than
    /// once — a second call sees `cache[style]` already set (success or failure) and no-ops.
    ///
    /// Any render call that lands before this completes simply sees `bank(for:)` return nil
    /// (not yet cached) and falls back to the font-rendering path, exactly like a
    /// missing/corrupt bundle would — no special-casing needed at call sites.
    func preloadAsync(style: String) async {
        guard cache[style] == nil else { return }
        let loaded = await Task.detached(priority: .userInitiated) {
            Self.loadBank(style: style)
        }.value
        cache[style] = loaded
    }

    /// Off-main-actor bank loader: the actual bundle file IO + gunzip + JSON decode, with no
    /// access to `cache` or any other actor-isolated state. `nonisolated` so it can genuinely
    /// run on a background executor (via `Task.detached`) instead of hopping onto the main
    /// actor the way a plain instance/static method on this @MainActor type otherwise would.
    nonisolated static func loadBank(style: String) -> HandBank? {
        HandBank.load(style: style)
    }
}
