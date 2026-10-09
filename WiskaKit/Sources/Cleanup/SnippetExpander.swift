import Core
import Foundation

/// Shows what a dictation becomes with the user's snippets (Settings → Snippets → Try it).
public enum SnippetPreview {
    public static func expand(_ text: String, snippets: [Snippet]) -> String {
        let extracted = SnippetExpander.extract(text, snippets: snippets)
        return SnippetExpander.fill(extracted.text, slots: extracted.slots)
    }
}

/// Voice snippets: a spoken phrase ("insert my signature") becomes a placeholder word before
/// cleanup, and the snippet's text replaces it after the style — so nothing rewrites the snippet.
enum SnippetExpander {
    static let placeholderStem = "wiskasnippet"

    /// Replaces every spoken snippet phrase with a placeholder word. Text without a phrase comes
    /// back untouched.
    static func extract(_ text: String, snippets: [Snippet]) -> (text: String, slots: [String: Snippet]) {
        let phrases = snippets
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .flatMap { snippet in snippet.spokenPhrases.map { (words: PhraseMatcher.bareWords($0), snippet: snippet) } }
            .filter { !$0.words.isEmpty }
            .sorted { $0.words.count > $1.words.count }   // the longest phrase wins
        guard !phrases.isEmpty else { return (text, [:]) }
        var slots: [String: Snippet] = [:]
        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
            let bareTokens = tokens.map(PhraseMatcher.bare)
            var current: [String] = []
            var index = 0
            var changed = false
            while index < tokens.count {
                guard let found = phrases.first(where: { phrase in
                    index + phrase.words.count <= tokens.count
                        && PhraseMatcher.matches(bareTokens[index..<index + phrase.words.count], phrase.words)
                }) else {
                    current.append(tokens[index])
                    index += 1
                    continue
                }
                changed = true
                let end = index + found.words.count
                let key = "\(placeholderStem)\(slots.count + 1)"
                slots[key] = found.snippet
                if found.snippet.text.contains("\n") {
                    if !current.isEmpty { lines.append(current.joined(separator: " ")) }
                    lines.append(key)
                    current = []
                } else {
                    // Keep the sentence's punctuation after the phrase ("address." → "<slot>.").
                    let trailing = String(tokens[end - 1].reversed().prefix { $0.isPunctuation }.reversed())
                    current.append(key + trailing)
                }
                index = end
            }
            if !changed {
                lines.append(line)   // untouched, spacing and all
            } else if !current.isEmpty {
                lines.append(current.joined(separator: " "))
            }
        }
        return slots.isEmpty ? (text, [:]) : (lines.joined(separator: "\n"), slots)
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
            // A snippet ending in punctuation keeps its own: drop the sentence's mark right after it.
            let ownEnd = snippet.text.last.map { ".!?…".contains($0) } ?? false
            if let regex = try? NSRegularExpression(pattern: "(?i)\(key)" + (ownEnd ? "[.!?…]?" : "")) {
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
}
