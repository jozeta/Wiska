import Core
import Foundation

/// One output line. Plain lines are ordinary sentences the writing style may finish;
/// lines made by a formatter (list items, greeting, sign-off, blank lines) keep their own form.
struct FormattedLine: Equatable, Sendable {
    var text: String
    var isPlain: Bool
}

/// Email category: the greeting and the sign-off go on their own lines.
enum EmailLayout {
    private static let nameEnders: Set<Character> = [",", ".", "!"]

    static func format(_ lines: [FormattedLine], rules: FormatRules) -> [FormattedLine] {
        var result = lines
        if let first = result.first, first.isPlain, let (greeting, body) = splitGreeting(first.text, rules: rules) {
            result.replaceSubrange(0...0, with: [FormattedLine(text: greeting, isPlain: false),
                                                 FormattedLine(text: "", isPlain: false),
                                                 FormattedLine(text: body, isPlain: true)])
        }
        if let last = result.last, last.isPlain, let (body, signOff) = splitSignOff(last.text, rules: rules) {
            result.removeLast()
            result.append(FormattedLine(text: body, isPlain: true))
            result.append(FormattedLine(text: "", isPlain: false))
            result += signOff.map { FormattedLine(text: $0, isPlain: false) }
        }
        return result
    }

    /// "Hi Anna, thanks…" → ("Hi Anna,", "Thanks…"); nil without a greeting or without a body.
    private static func splitGreeting(_ text: String, rules: FormatRules) -> (String, String)? {
        let tokens = words(text)
        guard let phrase = rules.greetings.filter({ startsWith(tokens, $0, at: 0) }).max(by: { $0.count < $1.count })
        else { return nil }
        var end = phrase.count   // tokens [0, end) form the greeting
        if let punctuated = (phrase.count - 1..<min(tokens.count, phrase.count + 3))
            .first(where: { tokens[$0].last.map(nameEnders.contains) ?? false }) {
            end = punctuated + 1
        } else {
            while end < min(tokens.count, phrase.count + 3), tokens[end].first?.isUppercase == true { end += 1 }
        }
        let body = tokens[end...].joined(separator: " ")
        guard !body.isEmpty else { return nil }
        let greeting = tokens[..<end].joined(separator: " ").trimmingCharacters(in: .punctuationCharacters)
        return (capitalized(greeting) + ",", capitalized(body))
    }

    /// "…tonight. Best regards, Johan." → ("…tonight.", ["Best regards,", "Johan"]).
    private static func splitSignOff(_ text: String, rules: FormatRules) -> (String, [String])? {
        let (body, sentence) = lastSentence(text)
        guard !body.isEmpty else { return nil }
        let tokens = words(sentence)
        guard let phrase = rules.signOffs.filter({ startsWith(tokens, $0, at: 0) }).max(by: { $0.count < $1.count })
        else { return nil }
        let name = Array(tokens[phrase.count...])
        guard name.count <= 3, name.allSatisfy({ $0.first?.isUppercase == true }) else { return nil }
        let closing = tokens[..<phrase.count].joined(separator: " ").trimmingCharacters(in: .punctuationCharacters)
        var lines = [capitalized(closing) + ","]
        if !name.isEmpty {
            lines.append(name.joined(separator: " ").trimmingCharacters(in: .punctuationCharacters))
        }
        return (body, lines)
    }

    /// Splits off the last sentence: everything after the last ". ", "! " or "? ".
    private static func lastSentence(_ text: String) -> (String, String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let searchable = trimmed.dropLast()   // ignore the closing punctuation itself
        guard let boundary = searchable.indices.last(where: { index in
            ".!?".contains(searchable[index]) && searchable.index(after: index) < searchable.endIndex
                && searchable[searchable.index(after: index)] == " "
        }) else { return ("", trimmed) }
        let body = String(trimmed[...boundary])
        let sentence = String(trimmed[trimmed.index(after: boundary)...]).trimmingCharacters(in: .whitespaces)
        return (body, sentence)
    }

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func startsWith(_ tokens: [String], _ phrase: [String], at start: Int) -> Bool {
        guard start + phrase.count <= tokens.count else { return false }
        return tokens[start..<start + phrase.count]
            .map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) } == phrase
    }

    private static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
