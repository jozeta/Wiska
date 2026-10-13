import Foundation

/// A word the user corrected right after Wiska pasted it: a candidate for the dictionary.
public struct Correction: Codable, Equatable, Hashable, Sendable {
    public let heard: String
    public let written: String

    public init(heard: String, written: String) {
        self.heard = heard
        self.written = written
    }
}

/// Compares a text field right after a paste with the same field a little later and finds the
/// words the user swapped inside the pasted text. Only mishearing-like fixes count: one to three
/// words for one to three, alike in spelling, and not just a different ordinary word ("their" →
/// "there" is grammar, not something to replace everywhere).
public enum CorrectionFinder {
    /// The longest stretch of changed words still read as corrections, not a rewrite.
    static let maxChangedWords = 12

    public static func corrections(before: String, after: String, pasted: String,
                                   isKnownWord: (String) -> Bool) -> [Correction] {
        guard before != after else { return [] }
        let pastedText = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pastedText.isEmpty, let pastedRange = before.range(of: pastedText, options: .backwards) else { return [] }
        let old = words(before)
        let new = words(after)
        // The changed middle: everything between the shared start and the shared end.
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix].text == new[prefix].text { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
              old[old.count - 1 - suffix].text == new[new.count - 1 - suffix].text { suffix += 1 }
        let oldMiddle = Array(old[prefix..<(old.count - suffix)])
        let newMiddle = Array(new[prefix..<(new.count - suffix)])
        guard !oldMiddle.isEmpty, !newMiddle.isEmpty,
              oldMiddle.count <= maxChangedWords, newMiddle.count <= maxChangedWords else { return [] }

        var found: [Correction] = []
        for (removed, added) in substitutions(oldMiddle.map(\.text), newMiddle.map(\.text)) {
            guard (1...3).contains(removed.count), (1...3).contains(added.count) else { continue }
            // Every corrected word was pasted by Wiska.
            let ranges = removed.map { oldMiddle[$0].range }
            guard ranges.allSatisfy({ pastedRange.contains($0.lowerBound) }) else { continue }
            let heard = removed.map { bare(oldMiddle[$0].text) }.joined(separator: " ")
            let written = added.map { bare(newMiddle[$0].text) }.joined(separator: " ")
            guard !heard.isEmpty, !written.isEmpty, heard != written, written.count <= 40,
                  !written.allSatisfy({ $0.isNumber || $0.isPunctuation }) else { continue }
            let heardWords = heard.split(separator: " ").map(String.init)
            let writtenWords = written.split(separator: " ").map(String.init)
            // A name or a term on either side, not one ordinary word for another.
            guard !(heardWords.allSatisfy(isKnownWord) && writtenWords.allSatisfy(isKnownWord)) else { continue }
            guard alike(heard, written) else { continue }
            found.append(Correction(heard: heard, written: written))
        }
        return found
    }

    /// Words with their place in the text.
    private static func words(_ text: String) -> [(text: String, range: Range<String.Index>)] {
        var result: [(String, Range<String.Index>)] = []
        var start: String.Index?
        for index in text.indices {
            if text[index].isWhitespace {
                if let begin = start { result.append((String(text[begin..<index]), begin..<index)) }
                start = nil
            } else if start == nil {
                start = index
            }
        }
        if let begin = start { result.append((String(text[begin...]), begin..<text.endIndex)) }
        return result
    }

    /// A word without the punctuation around it.
    private static func bare(_ word: String) -> String {
        word.trimmingCharacters(in: .punctuationCharacters.union(.symbols))
    }

    /// Runs of removed and added words (indices into `old` and `new`), from a word-level LCS.
    static func substitutions(_ old: [String], _ new: [String]) -> [(removed: [Int], added: [Int])] {
        let n = old.count, m = new.count
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = old[i] == new[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var result: [(removed: [Int], added: [Int])] = []
        var removed: [Int] = []
        var added: [Int] = []
        func flush() {
            if !removed.isEmpty || !added.isEmpty { result.append((removed, added)) }
            removed = []
            added = []
        }
        var i = 0, j = 0
        while i < n || j < m {
            if i < n, j < m, old[i] == new[j] {
                flush()
                i += 1
                j += 1
            } else if j < m, i == n || lcs[i][j + 1] >= lcs[i + 1][j] {
                added.append(j)
                j += 1
            } else {
                removed.append(i)
                i += 1
            }
        }
        flush()
        return result
    }

    /// Spelled alike: a case fix, or at most about half the letters different (Wisca/Wiska,
    /// Setterström/Zetterström), not a different word altogether.
    static func alike(_ a: String, _ b: String) -> Bool {
        let x = Array(a.lowercased()), y = Array(b.lowercased())
        if x == y { return true }
        var previous = Array(0...y.count)
        for i in 1...max(x.count, 1) where !x.isEmpty {
            var current = [i] + Array(repeating: 0, count: y.count)
            for j in 1...max(y.count, 1) where !y.isEmpty {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return Double(previous[y.count]) <= Double(max(x.count, y.count)) * 0.4
    }
}
