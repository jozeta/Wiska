import Foundation

/// A saved instruction for command mode (fn+⌃): say one of its phrases first, and the
/// instruction is used instead of your words.
public struct SavedCommand: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// What you say at the start of a command.
    public var phrases: [String]
    /// What Wiska asks the model to do.
    public var instruction: String

    public init(id: UUID = UUID(), phrases: [String], instruction: String) {
        self.id = id
        self.phrases = phrases
        self.instruction = instruction
    }

    /// The phrases, trimmed, without empty ones.
    public var spokenPhrases: [String] {
        phrases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// Why this command wouldn't work (shown in Settings). One-word phrases are fine: commands
    /// are only heard while fn+⌃ is held.
    public enum Problem: Equatable, Sendable {
        case noPhrase
        case noInstruction
    }

    private enum CodingKeys: String, CodingKey { case id, phrases, instruction }

    /// Missing keys get defaults, so older or hand-edited files (and future fields) still load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        phrases = try container.decodeIfPresent([String].self, forKey: .phrases) ?? []
        instruction = try container.decodeIfPresent(String.self, forKey: .instruction) ?? ""
    }

    public var problems: [Problem] {
        var problems: [Problem] = []
        if spokenPhrases.isEmpty { problems.append(.noPhrase) }
        if instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { problems.append(.noInstruction) }
        return problems
    }
}

/// Turns what was said with fn+⌃ into the model's instruction.
public enum CommandResolver {
    /// Words that join a command to more instructions ("formal and shorter").
    static let connectors: Set<String> = ["and", "then", "also", "plus", "och", "sen", "sedan", "samt",
                                          "und", "dann", "et", "puis", "y", "luego", "og", "så"]

    /// A command phrase said alone, or followed by a comma (or other mark) or a connector word,
    /// uses its instruction; words after it are added as "Also: …". Anything else — including
    /// an ordinary sentence that happens to start with a command word — is used as said.
    /// The saved command `spoken` starts with (alone or before a comma or "and"), if any.
    public static func matchedCommand(_ spoken: String, commands: [SavedCommand]) -> SavedCommand? {
        match(spoken, commands: commands)?.command
    }

    public static func resolve(_ spoken: String, commands: [SavedCommand]) -> String {
        guard let found = match(spoken, commands: commands) else { return spoken }
        let tokens = spoken.split(whereSeparator: \.isWhitespace).map(String.init)
        var instruction = found.command.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        var rest = tokens.dropFirst(found.words.count)
        // "formal and shorter": the joining word itself isn't part of the extra instruction.
        if let first = rest.first, connectors.contains(PhraseMatcher.bare(first)) {
            rest = rest.dropFirst()
        }
        let extra = rest.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !extra.isEmpty else { return instruction }
        if let last = instruction.last, !".!?…".contains(last) { instruction += "." }
        return "\(instruction) Also: \(extra)"
    }

    private static func match(_ spoken: String, commands: [SavedCommand]) -> (words: [String], command: SavedCommand)? {
        let tokens = spoken.split(whereSeparator: \.isWhitespace).map(String.init)
        let bareTokens = tokens.map(PhraseMatcher.bare)
        let phrases = commands
            .filter { $0.problems.isEmpty }
            .flatMap { command in command.spokenPhrases.map { (words: PhraseMatcher.bareWords($0), command: command) } }
            .filter { !$0.words.isEmpty }
            .sorted { $0.words.count > $1.words.count }   // the longest phrase wins
        func separated(after count: Int) -> Bool {
            count == tokens.count || tokens[count - 1].last?.isPunctuation == true || connectors.contains(bareTokens[count])
        }
        return phrases.first(where: { phrase in
            phrase.words.count <= tokens.count && PhraseMatcher.matches(bareTokens[0..<phrase.words.count], phrase.words)
                && separated(after: phrase.words.count)
        })
    }

    /// Created when the user has no commands file yet; editable and deletable.
    public static var defaults: [SavedCommand] {
        [SavedCommand(phrases: ["fix"], instruction: "Fix spelling and grammar. Change nothing else."),
         SavedCommand(phrases: ["formal"], instruction: "Rewrite in a formal, polite tone."),
         SavedCommand(phrases: ["shorter"], instruction: "Make it shorter. Keep the meaning."),
         SavedCommand(phrases: ["bullets"], instruction: "Turn it into a bulleted list.")]
    }
}
