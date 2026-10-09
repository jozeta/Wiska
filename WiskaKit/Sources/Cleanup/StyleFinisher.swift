import Core
import Foundation

/// How a cleaned sentence looks in each writing style, and code-safe output for the Code category.
enum StyleFinisher {
    private static let closers: Set<Character> = ["\"", "”", "'", "’", ")"]

    static func finish(_ text: String, style: WritingStyle, dictionary: PersonalDictionary) -> String {
        switch style {
        case .formal: formal(text)
        case .casual: dropFinalFullStop(formal(text))
        case .veryCasual: lowerCased(dropFinalFullStop(formal(text)), dictionary: dictionary)
        }
    }

    /// Capital first letter; ends like a sentence (looking past closing quotes and brackets).
    static func formal(_ text: String) -> String {
        guard let first = text.first else { return text }
        var result = first.uppercased() + text.dropFirst()
        if let last = result.last(where: { !closers.contains($0) }), !".?!…:".contains(last) { result += "." }
        return result
    }

    /// Exactly what was said: per line, no trailing full stop and no capital the engine added,
    /// unless the first word is "I" or a dictionary word.
    static func codeSafe(_ text: String, dictionary: PersonalDictionary) -> String {
        text.components(separatedBy: "\n").map { line in
            var line = line
            if line.hasSuffix("."), !line.hasSuffix("..") { line.removeLast() }
            guard let firstWord = line.split(separator: " ").first.map(String.init),
                  !keepsCapital(firstWord, dictionary: dictionary) else { return line }
            return line.prefix(1).lowercased() + line.dropFirst()
        }.joined(separator: "\n")
    }

    private static func dropFinalFullStop(_ text: String) -> String {
        guard text.hasSuffix("."), !text.hasSuffix("..") else { return text }
        return String(text.dropLast())
    }

    private static func lowerCased(_ text: String, dictionary: PersonalDictionary) -> String {
        var result = text.split(separator: " ", omittingEmptySubsequences: false).map { token in
            let word = String(token)
            let core = word.trimmingCharacters(in: .punctuationCharacters)
            if let spelling = dictionary.words.first(where: { $0.caseInsensitiveCompare(core) == .orderedSame }) {
                return word.replacingOccurrences(of: core, with: spelling)
            }
            return keepsCapital(word, dictionary: dictionary) || isAcronym(core) ? word : word.lowercased()
        }.joined(separator: " ")
        // Multi-word entries ("New York") span tokens: put their spelling back afterwards.
        for entry in dictionary.words where entry.contains(" ") {
            // Whole words only: "renew york" is not "New York".
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: entry) + "\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result),
                                                    withTemplate: NSRegularExpression.escapedTemplate(for: entry))
        }
        return result
    }

    /// "NASA", "EU": two or more letters, all upper-case.
    private static func isAcronym(_ word: String) -> Bool {
        word.count >= 2 && word.allSatisfy { $0.isUppercase }
    }

    /// "I", "I'm", "I'll"… and the user's own words keep their capitals.
    private static func keepsCapital(_ word: String, dictionary: PersonalDictionary) -> Bool {
        let core = word.trimmingCharacters(in: .punctuationCharacters)
        if core == "I" || core.hasPrefix("I'") || core.hasPrefix("I’") { return true }
        return dictionary.words.contains { $0.caseInsensitiveCompare(core) == .orderedSame }
    }
}
