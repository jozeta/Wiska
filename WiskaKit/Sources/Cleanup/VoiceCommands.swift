import Core
import Foundation

/// Spoken formatting commands, applied deterministically before any model sees the text.
public enum VoiceCommands {
    /// Trailing punctuation/space the transcriber puts around a spoken command.
    private static let trailing = "[\\s,.;:!?]*"

    /// A determiner right before a phrase means prose ("a new line of products", "en ny rad i
    /// tabellen"), and an infinitive marker before "scratch that" too ("need to scratch that itch").
    public static func apply(_ text: String, rules: LanguageRules = .default) -> String {
        var result = text
        if let cut = commandMatches(rules.scratchThat, in: result,
                                    blockedAfter: rules.determiners.union(rules.infinitiveMarkers))
            .last?.upperBound {
            result = String(result[cut...])
        }
        result = replace(rules.newParagraph, in: result, with: "\n\n", blockedAfter: rules.determiners)
        result = replace(rules.newLine, in: result, with: "\n", blockedAfter: rules.determiners)
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

    private static func replace(_ phrases: [String], in text: String, with replacement: String,
                                blockedAfter blocked: Set<String>) -> String {
        var result = text
        // Replace back to front so earlier ranges stay valid.
        for range in commandMatches(phrases, in: text, blockedAfter: blocked).reversed() {
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }
}
