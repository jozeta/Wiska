import Foundation

/// Spoken formatting commands, applied deterministically before any model sees the text.
public enum VoiceCommands {
    static let scratch = ["scratch that", "stryk det"]
    static let paragraph = ["new paragraph", "nytt stycke"]
    static let line = ["new line", "ny rad"]

    /// A determiner right before the phrase means it's prose: "a new line of products",
    /// "en ny rad i tabellen", "ett nytt stycke musik" (review I2).
    static let determiners: Set<String> = [
        "a", "an", "the", "this", "that", "these", "my", "our", "your", "their", "his", "her", "its",
        "en", "ett", "den", "det", "denna", "detta", "min", "mitt", "din", "ditt", "vår", "vårt",
        "er", "ert", "hans", "hennes", "deras", "sin", "sitt",
    ]
    /// "need to scratch that itch", "att stryka det" — an infinitive marker means prose.
    static let infinitiveMarkers: Set<String> = ["to", "att"]

    /// Trailing punctuation/space the transcriber puts around a spoken command.
    private static let trailing = "[\\s,.;:!?]*"

    public static func apply(_ text: String) -> String {
        var result = text
        if let cut = commandMatches(scratch, in: result, blockedAfter: determiners.union(infinitiveMarkers))
            .last?.upperBound {
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

    /// Ranges of command matches (leading spaces/commas + phrase + trailing punctuation),
    /// skipping matches whose preceding word marks them as ordinary prose.
    private static func commandMatches(_ phrases: [String], in text: String,
                                       blockedAfter blocked: Set<String>) -> [Range<String.Index>] {
        let regex = try! NSRegularExpression(pattern: "[ \\t,]*" + pattern(phrases) + trailing,
                                             options: [.caseInsensitive])
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let before = text[..<range.lowerBound]
            let previousWord = before.split(whereSeparator: { $0.isWhitespace }).last
                .map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
            // A sentence boundary right before the phrase always allows the command.
            let afterSentenceEnd = before.last.map { ".!?\n".contains($0) } ?? true
            if !afterSentenceEnd, let previousWord, blocked.contains(previousWord) { return nil }
            return range
        }
    }

    private static func replace(_ phrases: [String], in text: String, with replacement: String) -> String {
        var result = text
        // Replace back to front so earlier ranges stay valid.
        for range in commandMatches(phrases, in: text, blockedAfter: determiners).reversed() {
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }
}
