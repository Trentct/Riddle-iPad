import CoreGraphics
import UIKit

/// Pure per-character cursor layout: lays out a string left-to-right at a fixed cell
/// size, wrapping to the next line when a cell would overflow the available width or a
/// literal newline is encountered. No rendering, no randomness — the same math is shared
/// by QuillLayer's trajectory-bank rendering path and HandPickerView's 手泽 sample row,
/// so both agree on where every character lands. This unified per-char cursor is the
/// piece that lets a single sentence mix trajectory characters and font-fallback
/// characters (punctuation, digits, Latin) on one shared baseline.
enum GlyphLayout {
    struct Placement {
        let char: Character
        /// Top-left corner of this character's cell (its em-box origin) in the target
        /// coordinate space.
        let topLeft: CGPoint
    }

    /// - Parameters:
    ///   - text: source text; `"\n"` forces a line break, other characters (including
    ///     spaces) each occupy one fixed-width cell.
    ///   - cellWidth: fixed per-character advance (glyph size + spacing).
    ///   - lineHeight: vertical distance between successive lines.
    ///   - maxWidth: usable width per line, measured from `origin.x`.
    ///   - origin: top-left of the first character's cell.
    /// - Returns: one Placement per non-newline character, in input order. A line that
    ///   would otherwise be empty always gets at least one character (a single
    ///   wider-than-`maxWidth` cell never triggers a wrap before anything is placed).
    static func layout(_ text: String, cellWidth: CGFloat, lineHeight: CGFloat,
                        maxWidth: CGFloat, origin: CGPoint) -> [Placement] {
        var placements: [Placement] = []
        var x = origin.x
        var y = origin.y
        for char in text {
            if char == "\n" {
                x = origin.x
                y += lineHeight
                continue
            }
            if x + cellWidth > origin.x + maxWidth, x > origin.x {
                x = origin.x
                y += lineHeight
            }
            placements.append(Placement(char: char, topLeft: CGPoint(x: x, y: y)))
            x += cellWidth
        }
        return placements
    }

    /// Resolves one glyph placement's page-mapped strokes for the SDT trajectory rendering path:
    /// a bank trajectory (unit em-box → page coordinates anchored at `placement.topLeft`, scaled
    /// by `trajectoryGlyphSize`, then humanized with the trajectory-calibrated jitter amplitude
    /// 0.15 — see `Script.humanize`'s doc: its 0.4 default is calibrated for the font path's own
    /// ~100+px raster scale and would be ~3x too heavy applied directly at trajectory scale) if
    /// the bank has this character; otherwise a single-character font fallback (rasterize → thin
    /// → trace → simplify → humanize at the *font path's own* default amplitude 0.4, applied while
    /// still in raw raster-pixel space — matching how the font path itself calibrates jitter —
    /// then scaled by `fallbackTargetHeight / font.lineHeight` and translated into page
    /// coordinates the same way as the trajectory branch).
    ///
    /// Shared by `QuillLayer.writeViaBank` (animates the returned strokes stroke-by-stroke) and
    /// `HandPickerView.HandSampleRenderer.renderTrajectory` (accumulates them into one static
    /// image) — the only difference between those two callers is what they do with the strokes
    /// afterward, not how the strokes are produced.
    static func resolveTrajectoryStrokes<RNG: RandomNumberGenerator>(
        for placement: Placement,
        bank: HandBank,
        trajectoryGlyphSize: CGFloat,
        fallbackTargetHeight: CGFloat,
        fallbackFont: @autoclosure () -> UIFont?,
        rng: inout RNG
    ) -> [[CGPoint]] {
        let variant = Int.random(in: 0..<2, using: &rng)
        if let trajectory = bank.strokes(for: placement.char, variant: variant) ?? bank.strokes(for: placement.char, variant: 0) {
            let mapped = trajectory.map { stroke in
                stroke.map { p in
                    CGPoint(x: placement.topLeft.x + p.x * trajectoryGlyphSize,
                            y: placement.topLeft.y + p.y * trajectoryGlyphSize)
                }
            }
            return Script.humanize(mapped, amplitude: 0.15, using: &rng)
        }

        guard let font = fallbackFont() else { return [] }
        var mask = Script.rasterize(String(placement.char), font: font)
        Script.thin(&mask)
        let simplified = Script.trace(mask).map { Script.simplify($0) }
        guard !simplified.isEmpty else { return [] }
        let humanized = Script.humanize(simplified, using: &rng)   // font path default amplitude (0.4), untouched
        let scale = fallbackTargetHeight / font.lineHeight
        return humanized.map { stroke in
            stroke.map { p in
                CGPoint(x: placement.topLeft.x + p.x * scale, y: placement.topLeft.y + p.y * scale)
            }
        }
    }
}
