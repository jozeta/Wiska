import Foundation

public struct DiffToken: Equatable, Sendable {
    public let text: String
    /// Removed (in the heard text) or added/changed (in the pasted text).
    public let changed: Bool

    public init(text: String, changed: Bool) {
        self.text = text
        self.changed = changed
    }
}

/// What cleanup changed, word by word: the longest common subsequence of words, compared
/// without case and surrounding punctuation ("tuesday" = "Tuesday."), is unchanged.
public enum WordDiff {
    public static func diff(raw: String, final: String) -> (heard: [DiffToken], pasted: [DiffToken]) {
        let a = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        let b = final.split(whereSeparator: \.isWhitespace).map(String.init)
        let ka = a.map(key), kb = b.map(key)
        // lcs[i][j] = length of the LCS of ka[i...] and kb[j...].
        var lcs = Array(repeating: Array(repeating: 0, count: kb.count + 1), count: ka.count + 1)
        for i in stride(from: ka.count - 1, through: 0, by: -1) {
            for j in stride(from: kb.count - 1, through: 0, by: -1) {
                lcs[i][j] = ka[i] == kb[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var keptA = Set<Int>(), keptB = Set<Int>()
        var i = 0, j = 0
        while i < ka.count && j < kb.count {
            if ka[i] == kb[j] {
                keptA.insert(i); keptB.insert(j); i += 1; j += 1
            } else if lcs[i + 1][j] >= lcs[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return (a.indices.map { DiffToken(text: a[$0], changed: !keptA.contains($0)) },
                b.indices.map { DiffToken(text: b[$0], changed: !keptB.contains($0)) })
    }

    private static func key(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }
}
