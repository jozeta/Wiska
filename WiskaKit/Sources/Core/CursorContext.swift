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
            // Mid-word: skip to the next whitespace, so no partial word is kept.
            start = text[start..<index].firstIndex(where: \.isWhitespace) ?? index
        }
        var end = text.index(index, offsetBy: limit, limitedBy: text.endIndex) ?? text.endIndex
        if end < text.endIndex, !text[end].isWhitespace {
            end = text[index..<end].lastIndex(where: \.isWhitespace) ?? index
        }
        let before = String(text[start..<index]).replacing(/^\s+/, with: "")
        let after = String(text[index..<end]).replacing(/\s+$/, with: "")
        guard !(before + after).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        return before + marker + after
    }
}
