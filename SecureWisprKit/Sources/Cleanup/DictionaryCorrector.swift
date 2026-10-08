import Core
import Foundation

/// Applies the user's dictionary to text: explicit replacements, then conservative
/// near-miss correction of dictionary words. Pure and idempotent.
public enum DictionaryCorrector {
    public static func apply(_ text: String, dictionary: PersonalDictionary) -> String {
        var result = text
        for replacement in dictionary.replacements {
            result = replace(replacement, in: result)
        }
        // Longest entries first so "Ylva Zetterström" wins over a shorter overlapping entry.
        for entry in dictionary.words.sorted(by: { $0.count > $1.count }) {
            result = correctNearMisses(of: entry, in: result)
        }
        return result
    }

    // MARK: Replacements

    private static func phrasePattern(_ phrase: String) -> String {
        let words = phrase.split(whereSeparator: \.isWhitespace)
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
        // \b only makes sense next to word characters; use look-arounds so "(beta)" and "c++" work.
        return "(?<![\\p{L}\\p{N}])" + words.joined(separator: "[\\s,]+") + "(?![\\p{L}\\p{N}])"
    }

    private static func replace(_ replacement: Replacement, in text: String) -> String {
        guard let heard = try? NSRegularExpression(pattern: phrasePattern(replacement.heard),
                                                   options: [.caseInsensitive]),
              let written = try? NSRegularExpression(
                pattern: NSRegularExpression.escapedPattern(for: replacement.written), options: [.caseInsensitive])
        else { return text }
        let full = NSRange(text.startIndex..., in: text)
        // Matches that sit inside an existing occurrence of the written form are left alone,
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

    private static func correctNearMisses(of entry: String, in text: String) -> String {
        guard let limit = maxDistance(for: entry) else { return text }
        let entryWords = entry.split(whereSeparator: \.isWhitespace).count
        let entryLower = entry.lowercased()
        guard let tokenRegex = try? NSRegularExpression(pattern: "\\S+") else { return text }
        let tokens = tokenRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text) }
        guard tokens.count >= entryWords else { return text }

        var edits: [(Range<String.Index>, String)] = []
        var index = 0
        while index + entryWords <= tokens.count {
            let window = tokens[index..<(index + entryWords)]
            let span = window.first!.lowerBound..<window.last!.upperBound
            let raw = String(text[span])
            let leading = String(raw.prefix(while: { $0.isPunctuation }))
            let trailing = String(raw.reversed().prefix(while: { $0.isPunctuation }).reversed())
            let core = String(raw.dropFirst(leading.count).dropLast(trailing.count))
            let coreLower = core.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()

            if !core.isEmpty, core != entry,
               coreLower.first == entryLower.first,
               !(coreLower.hasPrefix(entryLower) && coreLower != entryLower),   // inflection: "Kvarnholmens"
               editDistance(coreLower, entryLower) <= limit {
                edits.append((span, leading + entry + trailing))
                index += entryWords
            } else {
                index += 1
            }
        }
        var result = text
        for (range, replacement) in edits.reversed() {
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    /// Levenshtein distance over characters.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            previous = current
        }
        return previous[b.count]
    }
}
