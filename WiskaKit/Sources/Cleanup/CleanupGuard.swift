import Core
import Foundation

/// Decides whether a model rewrite is faithful enough to paste.
public enum CleanupGuard {
    public enum Verdict: Equatable {
        case accept
        case reject(String)
    }

    /// Words the model may legitimately drop as fillers; not required to be kept.
    static let ambiguousFillers: Set<String> = [
        "like", "you", "know", "typ", "liksom", "alltså", "asså", "basically", "actually", "well",
    ]
    static let maxNewWordShare = 0.2
    static let questionWords: Set<String> = [
        "what", "who", "when", "where", "why", "how", "which", "is", "are", "can", "could", "do", "does",
        "vad", "vem", "när", "var", "varför", "hur", "vilken", "vilket", "vilka", "kan", "är",
    ]
    static let numberWords: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven",
        "twelve", "fifteen", "twenty", "thirty", "forty", "fifty", "hundred", "thousand", "half", "quarter",
        "noll", "ett", "två", "tre", "fyra", "fem", "sex", "sju", "åtta", "nio", "tio", "elva", "tolv",
        "femton", "tjugo", "trettio", "fyrtio", "femtio", "hundra", "tusen", "halv", "kvart",
    ]

    public static func check(original: String, cleaned: String, level: CleanupLevel) -> Verdict {
        let output = words(cleaned)
        guard !output.isEmpty else { return .reject("empty") }

        let input = words(original).filter { !RuleCleaner.fillers.contains($0) }
        let inputSet = Set(input)
        let spokeNumbers = input.contains { numberWords.contains($0) || $0.allSatisfy(\.isNumber) }
        let newWords = newWordCount(output, known: inputSet, digitsAllowed: spokeNumbers)
        if Double(newWords) > max(1, maxNewWordShare * Double(output.count)) {
            return .reject("new words")
        }
        // A spoken question must stay a question; a statement in its place is an answer.
        if let first = input.first, questionWords.contains(first), !cleaned.contains("?") {
            return .reject("question answered")
        }

        let required = input.filter { !ambiguousFillers.contains($0) }
        guard !required.isEmpty else { return .accept }
        let outputSet = Set(output)
        let kept = required.filter { outputSet.contains($0) }.count
        let minimumKept = level == .light ? 0.7 : 0.4
        if Double(kept) / Double(required.count) < minimumKept { return .reject("dropped words") }
        return .accept
    }

    /// Output words not present in the input. Not counted as new (review I4): words that only
    /// differ in spacing ("imorgon" → "i morgon") and — only if a number was spoken — digits
    /// ("two thirty" → "2:30"). Digits out of nowhere are how answers look ("3:15 pm").
    static func newWordCount(_ output: [String], known: Set<String>, digitsAllowed: Bool) -> Int {
        var count = 0
        var index = 0
        while index < output.count {
            let word = output[index]
            if known.contains(word) || (digitsAllowed && word.allSatisfy(\.isNumber)) {
                index += 1
            } else if index + 1 < output.count, known.contains(word + output[index + 1]) {
                index += 2
            } else {
                count += 1
                index += 1
            }
        }
        return count
    }

    static func words(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
