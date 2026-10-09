import Core
import Foundation

/// Turns a spoken enumeration ("first eggs, second milk, third bread") into numbered lines.
/// A marker counts only at the start of a clause (line start, after , ; : . ? ! or a conjunction),
/// and markers must run 1, 2, 3… with at least two items; anything else stays prose.
enum ListFormatter {
    private static let clauseEnders: Set<Character> = [",", ";", ":", ".", "?", "!"]
    private static let trailingStrip = CharacterSet(charactersIn: ",;.:")

    private struct Hit {
        let index: Int     // token index where the marker starts
        let length: Int    // tokens in the marker
        let item: Int      // 1-based item number
    }

    static func format(_ line: String, rules: FormatRules) -> [String]? {
        let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
        let hits = markerHits(tokens, rules: rules)
        guard hits.count >= 2, hits.map(\.item) == Array(1...hits.count),
              hits.dropFirst().allSatisfy({ continuesTheList($0.index, tokens, rules: rules) }) else { return nil }

        var lines: [String] = []
        let intro = trimmedItem(tokens[0..<hits[0].index], rules: rules, dropTrailingConjunctions: true)
        if !intro.isEmpty { lines.append(intro + ":") }
        for (number, hit) in hits.enumerated() {
            let end = number + 1 < hits.count ? hits[number + 1].index : tokens.count
            let item = trimmedItem(tokens[(hit.index + hit.length)..<end], rules: rules,
                                   dropTrailingConjunctions: number + 1 < hits.count)
            guard !item.isEmpty else { return nil }
            lines.append("\(number + 1). " + item.prefix(1).uppercased() + item.dropFirst())
        }
        return lines
    }

    private static func markerHits(_ tokens: [String], rules: FormatRules) -> [Hit] {
        var hits: [Hit] = []
        var index = 0
        while index < tokens.count {
            if isClauseStart(index, tokens, rules: rules), let hit = match(at: index, tokens, rules: rules) {
                hits.append(hit)
                index += hit.length
            } else {
                index += 1
            }
        }
        return hits
    }

    private static func isClauseStart(_ index: Int, _ tokens: [String], rules: FormatRules) -> Bool {
        guard index > 0 else { return true }
        let previous = tokens[index - 1]
        if let last = previous.last, clauseEnders.contains(last) { return true }
        return rules.conjunctions.contains(bare(previous))
    }

    /// Items after the first follow a comma, semicolon, colon or conjunction — never a sentence
    /// end: "First prize went to Anna. Second place went to Bob." is two sentences, not a list.
    private static func continuesTheList(_ index: Int, _ tokens: [String], rules: FormatRules) -> Bool {
        let previous = tokens[index - 1]
        if let last = previous.last, ",;:".contains(last) { return true }
        return rules.conjunctions.contains(bare(previous))
    }

    /// The longest marker form starting at `index`.
    private static func match(at index: Int, _ tokens: [String], rules: FormatRules) -> Hit? {
        var best: Hit?
        for (item, forms) in rules.listMarkers.enumerated() {
            for form in forms {
                let words = form.split(separator: " ").map(String.init)
                guard index + words.count <= tokens.count,
                      tokens[index..<index + words.count].map(bare) == words,
                      words.count > (best?.length ?? 0) else { continue }
                // "second place", "secondo me": a one-word marker used as an ordinary word.
                if words.count == 1, index + 1 < tokens.count, !tokens[index].hasSuffix(","),
                   rules.markerBlockers.contains(bare(tokens[index + 1])) { continue }
                best = Hit(index: index, length: words.count, item: item + 1)
            }
        }
        return best
    }

    private static func trimmedItem(_ slice: ArraySlice<String>, rules: FormatRules,
                                    dropTrailingConjunctions: Bool) -> String {
        var words = Array(slice)
        while dropTrailingConjunctions, let last = words.last, rules.conjunctions.contains(bare(last)) {
            words.removeLast()
        }
        return words.joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: trailingStrip)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Lower-cased, without surrounding punctuation.
    private static func bare(_ token: String) -> String {
        token.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }
}
