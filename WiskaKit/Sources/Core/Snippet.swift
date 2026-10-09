import Foundation

/// Saved text inserted by voice ("insert my signature").
public struct Snippet: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// What you say ("signature").
    public var name: String
    /// Other spoken names ("signatur", "sign-off").
    public var aliases: [String]
    /// Inserted exactly as written; may span lines.
    public var text: String

    public init(id: UUID = UUID(), name: String, aliases: [String] = [], text: String) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.text = text
    }

    /// The name and aliases, trimmed, without empty ones.
    public var spokenNames: [String] {
        ([name] + aliases).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
