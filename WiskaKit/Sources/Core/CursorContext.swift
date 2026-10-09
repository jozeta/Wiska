import Foundation

/// The text around the cursor that command mode gives the model when writing: up to `limit`
/// characters on each side, cut at word boundaries, with the cursor marked.
public enum CursorContext {
    public static let marker = "[cursor]"
    public static let limit = 1_500

    /// `cursor` is a UTF-16 offset, as Accessibility reports it. "" when there's no text.
    public static func window(text: String, cursor: Int, limit: Int = CursorContext.limit) -> String {
        let utf16 = text.utf16
        let offset = min(max(cursor, 0), utf16.count)
        // Rounded down to a character boundary (a cursor inside an emoji's surrogate pair).
        var index = utf16.index(utf16.startIndex, offsetBy: offset)
        while index > text.startIndex, index.samePosition(in: text) == nil { index = utf16.index(before: index) }

        var start = text.index(index, offsetBy: -limit, limitedBy: text.startIndex) ?? text.startIndex
        if start > text.startIndex, !text[text.index(before: start)].isWhitespace {
            // Mid-word: skip to the next whitespace, so no partial word is kept — unless there's
            // none nearby (Chinese, a long URL): then cut at a character.
            start = text[start..<index].prefix(100).firstIndex(where: \.isWhitespace) ?? start
        }
        var end = text.index(index, offsetBy: limit, limitedBy: text.endIndex) ?? text.endIndex
        if end < text.endIndex, !text[end].isWhitespace {
            end = text[index..<end].suffix(100).lastIndex(where: \.isWhitespace) ?? end
        }
        // The document's own "[cursor]" mustn't look like the real one.
        let before = String(text[start..<index]).replacing(/^\s+/, with: "")
            .replacingOccurrences(of: marker, with: "(cursor)")
        let after = String(text[index..<end]).replacing(/\s+$/, with: "")
            .replacingOccurrences(of: marker, with: "(cursor)")
        guard !(before + after).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        return before + marker + after
    }

    /// The UTF-16 range of a document to fetch for `window`: the limit plus a little on each side
    /// of the cursor (or selection), so a long document isn't copied whole.
    public static func readRange(cursor: Int, length: Int, count: Int,
                                 margin: Int = CursorContext.limit + 100) -> (location: Int, length: Int) {
        let cursor = min(max(cursor, 0), count)
        let start = max(0, cursor - margin)
        let end = min(count, cursor + max(length, 0) + margin)
        return (start, end - start)
    }
}
