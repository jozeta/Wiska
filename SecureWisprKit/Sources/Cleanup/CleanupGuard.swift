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

    public static func check(original: String, cleaned: String, level: CleanupLevel) -> Verdict {
        let output = words(cleaned)
        guard !output.isEmpty else { return .reject("empty") }

        let input = words(original).filter { !RuleCleaner.fillers.contains($0) }
        let inputSet = Set(input)
        let newWords = output.filter { !inputSet.contains($0) }.count
        if Double(newWords) / Double(output.count) > maxNewWordShare { return .reject("new words") }

        let required = input.filter { !ambiguousFillers.contains($0) }
        guard !required.isEmpty else { return .accept }
        let outputSet = Set(output)
        let kept = required.filter { outputSet.contains($0) }.count
        let minimumKept = level == .light ? 0.7 : 0.4
        if Double(kept) / Double(required.count) < minimumKept { return .reject("dropped words") }
        return .accept
    }

    static func words(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
