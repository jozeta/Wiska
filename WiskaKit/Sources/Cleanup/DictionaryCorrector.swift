import Core
import Foundation

/// Applies the user's dictionary to text: explicit replacements, then conservative
/// near-miss correction of dictionary words. Pure and idempotent.
public enum DictionaryCorrector {
    /// - Parameter isKnownWord: true for real Swedish/English words (the app backs it with the
    ///   system spell checker). Windows made only of known words are never corrected, so
    ///   "hann" never becomes "Hanna" and "klara" never becomes "Klara" (review C1).
    public static func apply(_ text: String, dictionary: PersonalDictionary,
                             isKnownWord: (String) -> Bool = { _ in false }) -> String {
        // One spelling of "é": composed and combining-mark forms must match each other.
        var result = text.precomposedStringWithCanonicalMapping
        for replacement in dictionary.replacements {
            result = replace(Replacement(heard: replacement.heard.precomposedStringWithCanonicalMapping,
                                         written: replacement.written.precomposedStringWithCanonicalMapping),
                             in: result)
        }
        return correctNearMisses(in: result, words: dictionary.words, isKnownWord: isKnownWord)
    }

    // MARK: Replacements

    private static func phrasePattern(_ phrase: String) -> String {
        let words = phrase.split(whereSeparator: \.isWhitespace)
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
        // \b only makes sense next to word characters; use look-arounds so "(beta)" and "c++" work.
        // \p{M}: a combining accent belongs to the word it follows.
        return "(?<![\\p{L}\\p{M}\\p{N}])" + words.joined(separator: "[\\s,]+") + "(?![\\p{L}\\p{M}\\p{N}])"
    }

    private static func replace(_ replacement: Replacement, in text: String) -> String {
        guard let heard = try? NSRegularExpression(pattern: phrasePattern(replacement.heard),
                                                   options: [.caseInsensitive]),
              // Case-sensitive: "github" → "GitHub" must still fire on "github" (review I1).
              let written = try? NSRegularExpression(
                pattern: NSRegularExpression.escapedPattern(for: replacement.written))
        else { return text }
        let full = NSRange(text.startIndex..., in: text)
        // Matches inside an existing occurrence of the written form are left alone,
        // so applying twice never yields "Secure Secure Wispr".
        let protected = written.matches(in: text, range: full).map(\.range)
        var result = text
        for match in heard.matches(in: text, range: full).reversed() {
            let inside = protected.contains { NSLocationInRange(match.range.location, $0) }
            guard !inside, let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: replacement.written)
        }
        return result
    }

    // MARK: Near misses

    static func maxDistance(for entry: String) -> Int? {
        let letters = entry.filter { !$0.isWhitespace }.count
        switch letters {
        case ..<5: return nil
        case 5...7: return 1
        default: return 2
        }
    }

    private struct Token {
        let range: Range<String.Index>
        let leading: String
        let trailing: String
        let core: String
        let lower: String
        let known: Bool
    }

    private struct Entry {
        let text: String
        let lower: String
        let words: Int
        let limit: Int
    }

    private static func correctNearMisses(in text: String, words: [String],
                                          isKnownWord: (String) -> Bool) -> String {
        // Longest entries first so "Ylva Zetterström" wins over a shorter overlapping entry.
        let entries = words.compactMap { word -> Entry? in
            guard let limit = maxDistance(for: word) else { return nil }
            return Entry(text: word, lower: word.lowercased(),
                         words: word.split(whereSeparator: \.isWhitespace).count, limit: limit)
        }.sorted { $0.text.count > $1.text.count }
        guard !entries.isEmpty else { return text }

        // Tokenise once (review I2).
        var tokens: [Token] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard let start = text[index...].firstIndex(where: { !$0.isWhitespace }) else { break }
            let end = text[start...].firstIndex(where: \.isWhitespace) ?? text.endIndex
            let raw = text[start..<end]
            let leading = String(raw.prefix(while: \.isPunctuation))
            let trailing = String(raw.reversed().prefix(while: \.isPunctuation).reversed())
            let core = leading.count + trailing.count >= raw.count
                ? "" : String(raw.dropFirst(leading.count).dropLast(trailing.count))
            tokens.append(Token(range: start..<end, leading: leading, trailing: trailing, core: core,
                                lower: core.lowercased(), known: !core.isEmpty && isKnownWord(core)))
            index = end
        }

        var consumed = Array(repeating: false, count: tokens.count)
        var edits: [(Range<String.Index>, String)] = []
        for entry in entries where tokens.count >= entry.words {
            var i = 0
            while i + entry.words <= tokens.count {
                let window = i..<(i + entry.words)
                defer { i += 1 }
                guard !window.contains(where: { consumed[$0] }) else { continue }
                let first = tokens[window.lowerBound], last = tokens[window.upperBound - 1]
                guard !first.lower.isEmpty, first.lower.first == entry.lower.first else { continue }
                // Inner tokens must not carry punctuation other than commas (no joining across ".").
                if entry.words > 1, window.dropLast().contains(where: {
                    !tokens[$0].trailing.isEmpty && tokens[$0].trailing != ","
                }) { continue }
                let lower = window.map { tokens[$0].lower }.joined(separator: " ")
                let core = window.map { tokens[$0].core }.joined(separator: " ")
                guard core != entry.text,
                      abs(lower.count - entry.lower.count) <= entry.limit,
                      !(lower.hasPrefix(entry.lower) && lower != entry.lower),      // "Kvarnholmens"
                      !window.allSatisfy({ tokens[$0].known }),                     // real words stay
                      editDistance(lower, entry.lower, limit: entry.limit) <= entry.limit
                else { continue }
                edits.append((first.range.lowerBound..<last.range.upperBound,
                              first.leading + entry.text + last.trailing))
                for t in window { consumed[t] = true }
            }
        }
        var result = text
        for (range, replacement) in edits.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) {
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    /// Levenshtein distance with two rolling rows; stops early once every value exceeds `limit`.
    static func editDistance(_ a: String, _ b: String, limit: Int = .max) -> Int {
        PhraseMatcher.editDistance(a, b, limit: limit)
    }
}
