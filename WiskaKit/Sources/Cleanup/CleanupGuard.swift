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
                             rules: LanguageRules = .default, grammar: Bool = false,
                             terms: Bool = false, isKnownWord: (String) -> Bool = { _ in false }) -> Verdict {
        let output = words(cleaned)
        guard !output.isEmpty else { return .reject("empty") }

        let input = words(original).filter { !rules.fillerSounds.contains($0) }
        let inputSet = Set(input)
        // Swedish IT terms the model wrote in place of misheard words ("Gira" → "Jira").
        let repaired = terms ? termRepairs(input, output: output, isKnownWord: isKnownWord) : []
        let spokeNumbers = input.contains { rules.numberWords.contains($0) || isNumeric($0) }
        // Grammar fixes change words ("buyed" → "bought"): a word near one that was said isn't new.
        let newWords = newWordCount(output, known: inputSet, digitsAllowed: spokeNumbers,
                                    nearWords: grammar ? input : [], termAllowance: repaired.count)
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
        let outputHasDigits = output.contains { isNumeric($0) }
        let joinedPairs = Set(zip(output, output.dropFirst()).map { $0 + $1 })
        let kept = required.filter { word in
            outputSet.contains(word) || joinedPairs.contains(word)   // "imorgon" → "i morgon"
                || (outputHasDigits && rules.numberWords.contains(word))   // "two thirty" → "2:30"
                || (grammar && output.contains { isNear(word, $0) })   // "go" fixed to "goes"
                || repaired.contains(word)
        }.count
        // Light must not remove any word besides fillers (with grammar: fix ~1 in 5);
        // Polished may drop false starts.
        let minimumKept = level == .light ? (grammar ? 0.8 : 1.0) : 0.4
        if Double(kept) / Double(required.count) < minimumKept { return .reject("dropped words") }
        return .accept
    }

    /// Words a grammar fix turns into each other: "a"/"an", "has"/"have", "buyed"/"bought".
    static func isNear(_ a: String, _ b: String) -> Bool {
        // Two short words are near only with one letter changed ("to"/"too"; not "on"/"me"),
        // but a short word may grow into a longer form ("do"/"does", "go"/"goes").
        let limit = max(a.count, b.count) <= 2 ? 1 : max(2, max(a.count, b.count) / 2)
        return PhraseMatcher.editDistance(a, b, limit: limit) <= limit
    }

    /// Misheard input words the output replaced with an IT term: gone from the output, and either
    /// inside a term word ("elastic" in "elasticsearch") or near one ("kubenetesklustret"/"kubernetes"
    /// + "klustret"). A real word must be closer still, one letter off ("gira"/"jira") or starting
    /// with the term ("puller"/"pull"), so "ploga" never becomes "deploya".
    static func termRepairs(_ input: [String], output: [String], isKnownWord: (String) -> Bool) -> Set<String> {
        let outputSet = Set(output)
        let termWords = output.filter(TechTerms.isTermWord)
        let termPairs = zip(output, output.dropFirst()).filter { TechTerms.isTermWord($0.0) }.map { $0.0 + $0.1 }
        return Set(input.filter { word in
            guard !outputSet.contains(word) else { return false }
            if termWords.contains(where: { $0.count > word.count && $0.contains(word) }) { return true }
            guard isKnownWord(word) else { return (termWords + termPairs).contains { isNear(word, $0) } }
            return termWords.contains { term in
                PhraseMatcher.editDistance(word, term, limit: 1) <= 1 || (term.count >= 4 && word.hasPrefix(term))
            }
        })
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
    static func newWordCount(_ output: [String], known: Set<String>, digitsAllowed: Bool,
                             nearWords: [String] = [], termAllowance: Int = 0) -> Int {
        var count = 0
        // Term words stand in for repaired words, one for each; more would be added content.
        var termAllowance = termAllowance
        var index = 0
        while index < output.count {
            let word = output[index]
            if known.contains(word) || (digitsAllowed && isNumeric(word))
                || nearWords.contains(where: { isNear(word, $0) }) {
                index += 1
            } else if termAllowance > 0, TechTerms.isTermWord(word) {
                termAllowance -= 1
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

    /// "5", "30", and ordinal digits like "5th", "1st", "3rd".
    static func isNumeric(_ word: String) -> Bool {
        let digits = word.prefix { $0.isNumber }
        return !digits.isEmpty && word.count - digits.count <= 2
            && word.dropFirst(digits.count).allSatisfy(\.isLetter)
    }

    static func words(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
