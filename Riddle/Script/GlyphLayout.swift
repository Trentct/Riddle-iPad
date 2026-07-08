import CoreGraphics

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
}
