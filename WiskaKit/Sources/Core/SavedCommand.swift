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

    public var problems: [Problem] {
        var problems: [Problem] = []
        if spokenPhrases.isEmpty { problems.append(.noPhrase) }
        if instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { problems.append(.noInstruction) }
        return problems
    }
}

/// Turns what was said with fn+⌃ into the model's instruction.
public enum CommandResolver {
    /// A command phrase at the start uses its instruction; words after it are added as
    /// "Also: …". Anything else is used as said.
    public static func resolve(_ spoken: String, commands: [SavedCommand]) -> String {
        let tokens = spoken.split(whereSeparator: \.isWhitespace).map(String.init)
        let bareTokens = tokens.map(PhraseMatcher.bare)
        let phrases = commands
            .filter { $0.problems.isEmpty }
            .flatMap { command in command.spokenPhrases.map { (words: PhraseMatcher.bareWords($0), command: command) } }
            .filter { !$0.words.isEmpty }
            .sorted { $0.words.count > $1.words.count }   // the longest phrase wins
        guard let found = phrases.first(where: { phrase in
            phrase.words.count <= tokens.count && PhraseMatcher.matches(bareTokens[0..<phrase.words.count], phrase.words)
        }) else { return spoken }
        var instruction = found.command.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let extra = tokens.dropFirst(found.words.count).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !extra.isEmpty else { return instruction }
        if let last = instruction.last, !".!?…".contains(last) { instruction += "." }
        return "\(instruction) Also: \(extra)"
    }

    /// Created when the user has no commands file yet; editable and deletable.
    public static var defaults: [SavedCommand] {
        [SavedCommand(phrases: ["fix"], instruction: "Fix spelling and grammar. Change nothing else."),
         SavedCommand(phrases: ["formal"], instruction: "Rewrite in a formal, polite tone."),
         SavedCommand(phrases: ["shorter"], instruction: "Make it shorter. Keep the meaning."),
         SavedCommand(phrases: ["bullets"], instruction: "Turn it into a bulleted list.")]
    }
}
