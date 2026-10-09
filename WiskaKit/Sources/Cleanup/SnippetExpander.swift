import Core
import Foundation

/// Voice snippets: "insert my signature" becomes a placeholder word before cleanup, and the
/// snippet's text replaces it after the style — so nothing ever rewrites the snippet.
enum SnippetExpander {
    static let placeholderStem = "wiskasnippet"

    static func extract(_ text: String, snippets: [Snippet], rules: FormatRules) -> (text: String, slots: [String: Snippet]) {
        let names = snippets.flatMap { snippet in
            snippet.spokenNames.map { (words: words($0), snippet: snippet) }
        }.filter { !$0.words.isEmpty }.sorted { $0.words.count > $1.words.count }
        guard !names.isEmpty else { return (text, [:]) }
        var slots: [String: Snippet] = [:]

        func slot(for snippet: Snippet) -> String {
            let key = "\(placeholderStem)\(slots.count + 1)"
            slots[key] = snippet
            return key
        }

        // Whole dictation: just "[my] address".
        let all = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var rest = all.map(bare)
        if let possessive = rules.possessives.first(where: { rest.starts(with: $0) }) { rest.removeFirst(possessive.count) }
        if let match = names.first(where: { matches(rest[...], $0.words) && rest.count == $0.words.count }) {
            return (slot(for: match.snippet), slots)
        }

        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
            var current: [String] = []
            var index = 0
            while index < tokens.count {
                guard let found = trigger(at: index, in: tokens, names: names, rules: rules) else {
                    current.append(tokens[index])
                    index += 1
                    continue
                }
                let key = slot(for: found.snippet)
                if found.snippet.text.contains("\n") {
                    if !current.isEmpty { lines.append(current.joined(separator: " ")) }
                    lines.append(key)
                    current = []
                } else {
                    // Keep the sentence's punctuation after the name ("address." → "<slot>.").
                    let last = tokens[found.end - 1]
                    let trailing = String(last.reversed().prefix { $0.isPunctuation }.reversed())
                    current.append(key + trailing)
                }
                index = found.end
            }
            if !current.isEmpty || tokens.isEmpty { lines.append(current.joined(separator: " ")) }
        }
        return (lines.joined(separator: "\n"), slots)
    }

    static func fill(_ text: String, slots: [String: Snippet]) -> String {
        guard !slots.isEmpty else { return text }
        var result = text
        // Longest keys first, so "wiskasnippet1" doesn't match inside "wiskasnippet10".
        for (key, snippet) in slots.sorted(by: { $0.key.count > $1.key.count }) {
            let lone = "(?im)^[ \\t]*\(key)[.,;:!?]?[ \\t]*$"
            if snippet.text.contains("\n"),
               let regex = try? NSRegularExpression(pattern: lone) {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result),
                                                        withTemplate: NSRegularExpression.escapedTemplate(for: snippet.text))
            }
            if let regex = try? NSRegularExpression(pattern: "(?i)\(key)") {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result),
                                                        withTemplate: NSRegularExpression.escapedTemplate(for: snippet.text))
            }
        }
        return result
    }

    /// A line that is only a placeholder (cleanup may have capitalised it or added a full stop).
    static func isPlaceholderLine(_ line: String) -> Bool {
        let core = line.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: .punctuationCharacters).lowercased()
        return core.hasPrefix(placeholderStem) && core.dropFirst(placeholderStem.count).allSatisfy(\.isNumber)
            && core.count > placeholderStem.count
    }

    static func placeholders(in text: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: "(?i)\(placeholderStem)\\d+") else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return Set(regex.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { text[$0].lowercased() } })
    }

    // MARK: Matching

    private static func trigger(at index: Int, in tokens: [String], names: [(words: [String], snippet: Snippet)],
                                rules: FormatRules) -> (snippet: Snippet, end: Int)? {
        let bareTokens = tokens.map(bare)
        guard let insert = rules.insertWords.first(where: { phrase in
            index + phrase.count <= bareTokens.count && Array(bareTokens[index..<index + phrase.count]) == phrase
        }) else { return nil }
        var start = index + insert.count
        if let possessive = rules.possessives.first(where: { phrase in
            start + phrase.count <= bareTokens.count && Array(bareTokens[start..<start + phrase.count]) == phrase
        }) { start += possessive.count }
        for name in names where start + name.words.count <= bareTokens.count {
            if matches(bareTokens[start..<start + name.words.count], name.words) {
                return (name.snippet, start + name.words.count)
            }
        }
        return nil
    }

    private static func matches(_ spoken: ArraySlice<String>, _ name: [String]) -> Bool {
        guard spoken.count == name.count else { return false }
        return zip(spoken, name).allSatisfy { said, word in
            said == word || said == word + "s" || said == word + "es"
                || (word.count >= 5 && DictionaryCorrector.editDistance(said, word, limit: 1) <= 1)
        }
    }

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map { bare(String($0)) }.filter { !$0.isEmpty }
    }

    private static func bare(_ token: String) -> String {
        token.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }
}
