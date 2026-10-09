import Foundation

/// Matches spoken words against a saved phrase (snippets, saved commands): case and punctuation
/// don't matter, a plural matches, and words of 5+ letters may be one letter off (a mishearing).
public enum PhraseMatcher {
    public static func bare(_ token: String) -> String {
        token.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }

    public static func bareWords(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map { bare(String($0)) }.filter { !$0.isEmpty }
    }

    public static func matches(_ spoken: ArraySlice<String>, _ phrase: [String]) -> Bool {
        guard spoken.count == phrase.count else { return false }
        return zip(spoken, phrase).allSatisfy { said, word in
            said == word || said == word + "s" || said == word + "es"
                || (word.count >= 5 && editDistance(said, word, limit: 1) <= 1)
        }
    }

    /// Levenshtein distance; stops early once every path exceeds `limit`.
    public static func editDistance(_ a: String, _ b: String, limit: Int = .max) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            var rowMin = current[0]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                rowMin = min(rowMin, current[j])
            }
            if rowMin > limit { return rowMin }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
