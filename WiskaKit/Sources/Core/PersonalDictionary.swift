import Foundation

/// A spoken form and how the user wants it written ("secure whisper" → "SecureWispr").
public struct Replacement: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var heard: String
    public var written: String

    public init(id: UUID = UUID(), heard: String, written: String) {
        self.id = id
        self.heard = heard
        self.written = written
    }
}

/// The user's own words and replacement rules.
public struct PersonalDictionary: Codable, Equatable, Sendable {
    public var words: [String]
    public var replacements: [Replacement]

    public init(words: [String] = [], replacements: [Replacement] = []) {
        self.words = words
        self.replacements = replacements
    }

    /// Trimmed, without empty entries, first occurrence wins for case-insensitive duplicates.
    public func normalized() -> PersonalDictionary {
        var seenWords = Set<String>()
        let words = self.words
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seenWords.insert($0.lowercased()).inserted }
        var seenHeard = Set<String>()
        let replacements = self.replacements.compactMap { replacement -> Replacement? in
            let heard = replacement.heard.trimmingCharacters(in: .whitespacesAndNewlines)
            let written = replacement.written.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !heard.isEmpty, !written.isEmpty, seenHeard.insert(heard.lowercased()).inserted else { return nil }
            return Replacement(id: replacement.id, heard: heard, written: written)
        }
        return PersonalDictionary(words: words, replacements: replacements)
    }
}
