import Foundation

/// Spoken formatting commands, applied deterministically before any model sees the text.
public enum VoiceCommands {
    static let scratch = ["scratch that", "stryk det"]
    static let paragraph = ["new paragraph", "nytt stycke"]
    static let line = ["new line", "ny rad"]

    /// Trailing punctuation/space the transcriber puts around a spoken command.
    private static let trailing = "[\\s,.;:!?]*"

    public static func apply(_ text: String) -> String {
        var result = text
        if let cut = lastMatchEnd(of: scratch, in: result) {
            result = String(result[cut...])
        }
        result = replace(paragraph, in: result, with: "\n\n")
        result = replace(line, in: result, with: "\n")
        // Trim spaces only: a trailing "\n" from a final "new line" is intentional.
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Whole-word, case-insensitive alternation; words may be separated by spaces or commas.
    private static func pattern(_ phrases: [String]) -> String {
        let alternatives = phrases.map { phrase in
            phrase.split(separator: " ")
                .map { NSRegularExpression.escapedPattern(for: String($0)) }
                .joined(separator: "[\\s,]+")
        }
        return "\\b(?:" + alternatives.joined(separator: "|") + ")\\b"
    }

    private static func lastMatchEnd(of phrases: [String], in text: String) -> String.Index? {
        let regex = try! NSRegularExpression(pattern: pattern(phrases) + trailing, options: [.caseInsensitive])
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard let last = matches.last, let range = Range(last.range, in: text) else { return nil }
        return range.upperBound
    }

    private static func replace(_ phrases: [String], in text: String, with replacement: String) -> String {
        // Leading spaces/commas are eaten; a leading period is kept ("Hello. New line." → "Hello.\n").
        let regex = try! NSRegularExpression(pattern: "[ \\t,]*" + pattern(phrases) + trailing,
                                             options: [.caseInsensitive])
        return regex.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text),
            withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
        )
    }
}
