import Foundation

/// Saved text inserted by voice: say one of its phrases ("insert my signature") anywhere in a
/// dictation, and the text is put in exactly as written.
public struct Snippet: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// What you say — exactly these words, anywhere in a dictation.
    public var phrases: [String]
    /// What is inserted, exactly as written; may span lines.
    public var text: String

    public init(id: UUID = UUID(), phrases: [String], text: String) {
        self.id = id
        self.phrases = phrases
        self.text = text
    }

    /// The phrases, trimmed, without empty ones.
    public var spokenPhrases: [String] {
        phrases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// Why this snippet wouldn't work as expected (shown in Settings).
    public enum Problem: Equatable, Sendable {
        /// Nothing to say: it can never be inserted.
        case noPhrase
        /// Nothing to insert.
        case noText
        /// A one-word phrase also fires in ordinary sentences.
        case oneWordPhrase(String)
    }

    public var problems: [Problem] {
        var problems: [Problem] = []
        if spokenPhrases.isEmpty { problems.append(.noPhrase) }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { problems.append(.noText) }
        for phrase in spokenPhrases where !phrase.contains(where: \.isWhitespace) {
            problems.append(.oneWordPhrase(phrase))
        }
        return problems
    }

    private enum CodingKeys: String, CodingKey {
        case id, phrases, text
        case name, aliases   // the first version stored these
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        if let phrases = try container.decodeIfPresent([String].self, forKey: .phrases) {
            self.phrases = phrases
        } else {
            let name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
            let aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
            phrases = ([name] + aliases).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(phrases, forKey: .phrases)
        try container.encode(text, forKey: .text)
    }
}
