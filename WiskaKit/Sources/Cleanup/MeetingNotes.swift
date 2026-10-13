import Core
import Foundation
import FoundationModels

/// Meeting notes from a labelled transcript ("[0:12] Anna: …"): a summary, decisions and action
/// items with who owns them. On-device models read about 3,000 words at a time, so a long meeting
/// is summarised in parts and the parts' notes are combined.
@MainActor
public enum MeetingNotes {
    /// Answers `prompt` under `system` instructions (Apple Intelligence or Gemma).
    public typealias Generate = @MainActor (_ system: String, _ prompt: String) async throws -> String

    static let partInstructions = """
    You take notes of a meeting from its transcript. Each line starts with a time and the speaker's name. \
    Write: a short summary as bullet points; decisions made; action items as "Name: task" with a deadline if \
    one was said. Use the speakers' names exactly as written. Only write what was said — never invent. \
    Use the headings Summary, Decisions and Action items. If there are none of something, write "None".
    """

    static let combineInstructions = """
    These are notes from consecutive parts of one meeting. Combine them into one set of notes with the headings \
    Summary, Decisions and Action items. Merge repeats, keep every action item with its owner, keep names exactly \
    as written, never invent anything.
    """

    public static func write(_ transcript: String, language: Language?, partWords: Int = 1_800,
                             generate: Generate, progress: @MainActor (Double) -> Void) async throws -> String {
        let languageNote = language.map { "\n\nWrite the notes in \(englishName($0))." } ?? "\n\nWrite the notes in the transcript's language."
        let parts = parts(transcript, maxWords: partWords)
        progress(0)
        guard parts.count > 1 else {
            let notes = try await generate(partInstructions, "Transcript:\n\(transcript)" + languageNote)
            progress(1)
            return clean(notes)
        }
        var partNotes: [String] = []
        for (index, part) in parts.enumerated() {
            try Task.checkCancellation()
            let notes = try await generate(partInstructions, "Transcript (part \(index + 1) of \(parts.count)):\n\(part)" + languageNote)
            partNotes.append(clean(notes))
            progress(Double(index + 1) / Double(parts.count + 1))
        }
        let combined = try await generate(combineInstructions,
                                          partNotes.enumerated().map { "Part \($0.offset + 1):\n\($0.element)" }
                                              .joined(separator: "\n\n") + languageNote)
        progress(1)
        return clean(combined)
    }

    /// Whole paragraphs (turns), gathered up to `maxWords` per part.
    static func parts(_ transcript: String, maxWords: Int) -> [String] {
        var parts: [String] = []
        var current: [String] = []
        var words = 0
        for paragraph in transcript.components(separatedBy: "\n\n") where !paragraph.isEmpty {
            let count = Log.words(paragraph)
            if !current.isEmpty, words + count > maxWords {
                parts.append(current.joined(separator: "\n\n"))
                current = []
                words = 0
            }
            current.append(paragraph)
            words += count
        }
        if !current.isEmpty { parts.append(current.joined(separator: "\n\n")) }
        return parts
    }

    /// Markdown emphasis the models like to add, which plain-text notes don't need.
    static func clean(_ notes: String) -> String {
        notes.replacingOccurrences(of: "**", with: "")
            .replacing(/(?m)^#+\s*/, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func englishName(_ language: Language) -> String {
        Locale(identifier: "en").localizedString(forLanguageCode: language.locale.language.languageCode?.identifier ?? "en")
            ?? "the transcript's language"
    }

    /// Apple Intelligence, when this Mac has it.
    public static var appleAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    public static let apple: Generate = { system, prompt in
        try await LanguageModelSession(instructions: system).respond(to: prompt).content
    }
}
