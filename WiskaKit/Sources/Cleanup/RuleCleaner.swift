import Foundation

/// Deterministic cleanup used when the model is skipped, unavailable, slow or rejected.
/// Only removes words that are never real words; ambiguous ones ("like", "typ") are left alone.
public enum RuleCleaner {
    /// Not "er" — that's a common Swedish word ("your").
    public static let fillers: Set<String> = [
        "um", "umm", "uh", "uhm", "erm", "ehm", "hmm",   // English
        "öh", "eh", "äh", "ehh",                          // Swedish
    ]
    private static let terminal: Set<Character> = [".", "?", "!", "…", ":"]

    public static func clean(_ text: String) -> String {
        var words: [String] = []
        for token in text.split(whereSeparator: \.isWhitespace).map(String.init) {
            let core = normalized(token)
            if fillers.contains(core) { continue }
            if let previous = words.last, !core.isEmpty, normalized(previous) == core { continue }
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
