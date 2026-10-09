import Foundation

/// Settings → Speech → Compare on my voice: sentences to read, and how far a transcript is from them.
public enum VoiceBenchmark {
    public static let sentences = [
        "Jag har ett stort hus och en liten trädgård.",
        "Mötet börjar på torsdag efter lunch i det stora rummet.",
        "Sju sjösjuka sjömän sköttes av sju sköna sjuksköterskor.",
        "Johan och Anna åkte till Göteborg för att köpa en ny cykel.",
        "Kundtjänstmedarbetaren skickade en sammanfattning av arbetsmiljöundersökningen.",
    ]

    public static var reference: String { sentences.joined(separator: " ") }

    /// Lowercased words; punctuation ignored.
    static func words(_ text: String) -> [String] {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    /// Word-level edits (substitutions, insertions, deletions) per reference word.
    public static func wordErrorRate(reference: String, hypothesis: String) -> Double {
        let ref = words(reference), hyp = words(hypothesis)
        guard !ref.isEmpty else { return hyp.isEmpty ? 0 : 1 }
        var previous = Array(0...hyp.count)
        for i in 1...ref.count {
            var current = [i] + Array(repeating: 0, count: hyp.count)
            for j in stride(from: 1, through: hyp.count, by: 1) {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (ref[i - 1] == hyp[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return Double(previous[hyp.count]) / Double(ref.count)
    }
}
