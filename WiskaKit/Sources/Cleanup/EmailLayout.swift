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
    /// Lower-case words that still address people ("Hi everyone,", "Hej alla,").
    private static let groupWords: Set<String> = ["team", "all", "everyone", "everybody", "there", "folks", "guys",
                                                  "alla", "allihop", "zusammen", "alle", "tous", "todos", "todas",
                                                  "tutti", "allemaal", "iedereen"]

    static func format(_ lines: [FormattedLine], rules: FormatRules) -> [FormattedLine] {
        var result = lines
        // A greeting or sign-off may stand on its own line when the email has other lines ("new line").
        let multiline = lines.count > 1
        if let first = result.first, first.isPlain,
           let (greeting, body) = splitGreeting(first.text, rules: rules, alone: multiline) {
            var replacement = [FormattedLine(text: greeting, isPlain: false), FormattedLine(text: "", isPlain: false)]
            if !body.isEmpty { replacement.append(FormattedLine(text: body, isPlain: true)) }
            result.replaceSubrange(0...0, with: replacement)
        }
        if let last = result.last, last.isPlain,
           let (body, signOff) = splitSignOff(last.text, rules: rules, alone: multiline) {
            result.removeLast()
            if !body.isEmpty { result.append(FormattedLine(text: body, isPlain: true)) }
            result.append(FormattedLine(text: "", isPlain: false))
            result += signOff.map { FormattedLine(text: $0, isPlain: false) }
        }
        return result
    }

    /// "Hi Anna, thanks…" → ("Hi Anna,", "Thanks…"); nil without a greeting, or without a body
    /// unless the greeting may stand `alone` on its line.
    private static func splitGreeting(_ text: String, rules: FormatRules, alone: Bool) -> (String, String)? {
        let tokens = words(text)
        guard let phrase = rules.greetings.filter({ startsWith(tokens, $0, at: 0) }).max(by: { $0.count < $1.count })
        else { return nil }
        var end = phrase.count   // tokens [0, end) form the greeting
        if let punctuated = (phrase.count - 1..<min(tokens.count, phrase.count + 3))
            .first(where: { tokens[$0].last.map(nameEnders.contains) ?? false }),
           tokens[phrase.count..<punctuated + 1].allSatisfy(isNameWord) {
            end = punctuated + 1
        } else {
            while end < min(tokens.count, phrase.count + 3), tokens[end].first?.isUppercase == true,
                  !isI(tokens[end]) { end += 1 }
        }
        let body = tokens[end...].joined(separator: " ")
        guard !body.isEmpty || alone else { return nil }
        let greeting = tokens[..<end].joined(separator: " ").trimmingCharacters(in: .punctuationCharacters)
        return (capitalized(greeting) + ",", capitalized(body))
    }

    /// "…tonight. Best regards, Johan." → ("…tonight.", ["Best regards,", "Johan"]); the body may be
    /// empty only when the sign-off may stand `alone` on its line.
    private static func splitSignOff(_ text: String, rules: FormatRules, alone: Bool) -> (String, [String])? {
        let (body, sentence) = lastSentence(text)
        guard !body.isEmpty || alone else { return nil }
        let tokens = words(sentence)
        guard let phrase = rules.signOffs.filter({ startsWith(tokens, $0, at: 0) }).max(by: { $0.count < $1.count })
        else { return nil }
        let name = Array(tokens[phrase.count...])
        guard name.count <= 3, name.allSatisfy(isSignOffName) else { return nil }
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

    /// A word in a greeting's name: capitalised ("Anna"), but not "I"; or a group ("everyone").
    private static func isNameWord(_ token: String) -> Bool {
        let bare = token.trimmingCharacters(in: .punctuationCharacters)
        return (bare.first?.isUppercase == true && !isI(bare)) || groupWords.contains(bare.lowercased())
    }

    /// Capitalised words that are pronouns, not names ("Danke Ihnen", "Thanks, I").
    private static let capitalisedPronouns: Set<String> = ["I", "Sie", "Ihnen", "Ihr", "Ihre", "Euch", "Dir",
                                                           "Dich", "Du"]

    private static func isSignOffName(_ token: String) -> Bool {
        let bare = token.trimmingCharacters(in: .punctuationCharacters)
        return bare.first?.isUppercase == true && !capitalisedPronouns.contains(bare)
    }

    private static func isI(_ token: String) -> Bool {
        let bare = token.trimmingCharacters(in: .punctuationCharacters)
        return bare == "I" || bare.hasPrefix("I'") || bare.hasPrefix("I’")
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
