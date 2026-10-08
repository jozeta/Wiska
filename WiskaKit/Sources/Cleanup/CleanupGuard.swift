import Core
import Foundation

/// Decides whether a model rewrite is faithful enough to paste.
public enum CleanupGuard {
    public enum Verdict: Equatable {
        case accept
        case reject(String)
    }

    static let maxNewWordShare = 0.2

    public static func check(original: String, cleaned: String, level: CleanupLevel,
                             rules: LanguageRules = .default) -> Verdict {
        let output = words(cleaned)
        guard !output.isEmpty else { return .reject("empty") }

        let input = words(original).filter { !rules.fillerSounds.contains($0) }
        let inputSet = Set(input)
        let spokeNumbers = input.contains { rules.numberWords.contains($0) || $0.allSatisfy(\.isNumber) }
        let newWords = newWordCount(output, known: inputSet, digitsAllowed: spokeNumbers)
        if Double(newWords) > max(1, maxNewWordShare * Double(output.count)) {
            return .reject("new words")
        }
        // A spoken question must stay a question; a statement in its place is an answer.
        if let first = input.first, rules.questionWords.contains(first), !cleaned.contains("?") {
            return .reject("question answered")
        }

        let required = requiredWords(input, rules: rules)
        guard !required.isEmpty else { return .accept }
        let outputSet = Set(output)
        let outputHasDigits = output.contains { $0.allSatisfy(\.isNumber) }
        let joinedPairs = Set(zip(output, output.dropFirst()).map { $0 + $1 })
        let kept = required.filter { word in
            outputSet.contains(word) || joinedPairs.contains(word)   // "imorgon" → "i morgon"
                || (outputHasDigits && rules.numberWords.contains(word))   // "two thirty" → "2:30"
        }.count
        // Light must not remove any word besides fillers; Polished may drop false starts.
        let minimumKept = level == .light ? 1.0 : 0.4
        if Double(kept) / Double(required.count) < minimumKept { return .reject("dropped words") }
        return .accept
    }

    /// Input words that must survive cleanup: everything but fillers and filler phrases.
    static func requiredWords(_ input: [String], rules: LanguageRules = .default) -> [String] {
        var droppable = Set<Int>()
        for phrase in rules.fillerPhrases where phrase.count <= input.count {
            for start in 0...(input.count - phrase.count) where Array(input[start..<start + phrase.count]) == phrase {
                droppable.formUnion(start..<start + phrase.count)
            }
        }
        return input.enumerated()
            .filter { !droppable.contains($0.offset) && !rules.softFillers.contains($0.element) }
            .map(\.element)
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
