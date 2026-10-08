import Core
import Foundation

/// Deterministic cleanup used when the model is skipped, unavailable, slow or rejected.
/// Only removes filler sounds (never real words); soft fillers ("like", "typ") are left alone.
public enum RuleCleaner {
    private static let terminal: Set<Character> = [".", "?", "!", "…", ":"]

    public static func clean(_ text: String, rules: LanguageRules = .default) -> String {
        var words: [String] = []
        for token in text.split(whereSeparator: \.isWhitespace).map(String.init) {
            let core = normalized(token)
            if rules.fillerSounds.contains(core) { continue }
            if let previous = words.last, !core.isEmpty, normalized(previous) == core,
               !rules.legitimateRepeats.contains(core) { continue }
            words.append(token)
        }
        guard var result = words.isEmpty ? nil : words.joined(separator: " ") else { return "" }
        result = result.prefix(1).uppercased() + result.dropFirst()
        if let last = result.last, !terminal.contains(last) { result += "." }
        return result
    }

    static func normalized(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }
}
