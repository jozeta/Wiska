import Core
import Foundation
import FoundationModels

/// Command mode: rewrites the selected text following a spoken instruction, on-device.
@MainActor
public final class FoundationModelsEditor: TextEditor {
    /// A rewrite produces about as many tokens as it reads, and both must fit the on-device
    /// model's ~4,096-token context: about 600 words in, 600 out.
    public static let maxWords = 600
    static let instructions = """
    You edit text. Apply the instruction to the text. \
    Keep the text's language unless the instruction asks for another. \
    Output only the edited text, without quotes or commentary.
    """

    private let isAvailable: @MainActor () -> Bool
    private let respond: @MainActor (String) async throws -> String
    private let timeout: (Int) -> Duration

    public convenience init() {
        self.init(isAvailable: {
            if case .available = SystemLanguageModel.default.availability { return true }
            return false
        }, respond: { prompt in
            let session = LanguageModelSession(instructions: FoundationModelsEditor.instructions)
            return try await session.respond(to: prompt, options: GenerationOptions(temperature: 0)).content
        }, timeout: FoundationModelsEditor.timeout(forWords:))
    }

    init(isAvailable: @escaping @MainActor () -> Bool, respond: @escaping @MainActor (String) async throws -> String,
         timeout: @escaping (Int) -> Duration) {
        self.isAvailable = isAvailable
        self.respond = respond
        self.timeout = timeout
    }

    /// Generation takes time per word: 10 s, or ~60 ms per word for longer selections.
    static func timeout(forWords words: Int) -> Duration {
        .milliseconds(max(10_000, words * 60))
    }

    static func prompt(text: String, instruction: String) -> String {
        "Instruction: \(instruction)\n\nText:\n\(text)"
    }

    /// The model's answer, without wrapping quotes, inside the original's leading and trailing
    /// whitespace — a triple-clicked paragraph keeps its newline, an indented line its indent.
    static func rewrap(original: String, edited: String) -> String {
        let leading = original.prefix { $0.isWhitespace }
        let trailing = String(original.reversed().prefix { $0.isWhitespace }.reversed())
        // Strip quotes the model wrapped its answer in — unless the selection was itself quoted.
        let quoted = CleanupPipeline.stripWrappingQuotes(original) != original.trimmingCharacters(in: .whitespacesAndNewlines)
        let core = quoted ? edited.trimmingCharacters(in: .whitespacesAndNewlines)
                          : CleanupPipeline.stripWrappingQuotes(edited)
        return core.isEmpty ? "" : leading + core + trailing
    }

    public func edit(_ text: String, instruction: String, language: Language?) async throws -> String {
        let words = text.split(whereSeparator: \.isWhitespace).count
        guard words <= Self.maxWords else { throw EditError.tooLong }
        guard isAvailable() else { throw EditError.unavailable }
        let output: String
        do {
            output = try await race(Self.prompt(text: text, instruction: instruction), within: timeout(words))
        } catch {
            throw EditError.failed
        }
        let edited = Self.rewrap(original: text, edited: output)
        guard !edited.isEmpty else { throw EditError.failed }
        return edited
    }

    /// Whichever finishes first wins; never waits for the model to honour cancellation.
    private func race(_ prompt: String, within limit: Duration) async throws -> String {
        let respond = respond
        return try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            let work = Task { @MainActor in
                do { once.resume(.success(try await respond(prompt))) } catch { once.resume(.failure(error)) }
            }
            Task {
                try? await Task.sleep(for: limit)
                once.resume(.failure(CleanupTimeout()))
                work.cancel()
            }
        }
    }
}
