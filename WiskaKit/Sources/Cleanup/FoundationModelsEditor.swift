import Core
import Foundation
import FoundationModels

/// Command mode: rewrites the selected text following a spoken instruction, on-device.
@MainActor
public final class FoundationModelsEditor: TextEditor {
    private static let log = Log.logger("Cleanup")

    private let isAvailable: @MainActor () -> Bool
    private let respond: @MainActor (_ instructions: String, _ prompt: String) async throws -> String
    private let timeout: (Int) -> Duration

    public convenience init() {
        self.init(isAvailable: {
            if case .available = SystemLanguageModel.default.availability { return true }
            return false
        }, respond: { instructions, prompt in
            let session = LanguageModelSession(instructions: instructions)
            return try await session.respond(to: prompt, options: GenerationOptions(temperature: 0)).content
        }, timeout: EditPrompts.timeout(forWords:))
    }

    init(isAvailable: @escaping @MainActor () -> Bool, respond: @escaping @MainActor (_ instructions: String, _ prompt: String) async throws -> String,
         timeout: @escaping (Int) -> Duration) {
        self.isAvailable = isAvailable
        self.respond = respond
        self.timeout = timeout
    }

    /// What a model error means for the user: a refusal won't change on retry; a full context
    /// means the selection is too long.
    static func editError(for error: Error) -> EditError {
        guard let generation = error as? LanguageModelSession.GenerationError else { return .failed }
        switch generation {
        case .guardrailViolation, .refusal: return .refused
        case .exceededContextWindowSize: return .tooLong
        default: return .failed
        }
    }

    public func edit(_ text: String, instruction: String, language: Language?) async throws -> String {
        let words = text.split(whereSeparator: \.isWhitespace).count
        guard words <= EditPrompts.maxWords else {
            Self.log.notice("apple edit: selection too long (\(words) words, limit \(EditPrompts.maxWords))")
            throw EditError.tooLong
        }
        guard isAvailable() else {
            Self.log.notice("apple edit: Apple Intelligence unavailable")
            throw EditError.unavailable
        }
        let respond = respond
        let output = try await answer("edit", words: words) {
            try await respond(EditPrompts.instructions, EditPrompts.prompt(text: text, instruction: instruction))
        }
        return try EditPrompts.cleanEdited(original: text, output: output)
    }

    public func write(instruction: String, context: String?, language: Language?) async throws -> String {
        guard isAvailable() else {
            Self.log.notice("apple write: Apple Intelligence unavailable")
            throw EditError.unavailable
        }
        let words = (instruction + " " + (context ?? "")).split(whereSeparator: \.isWhitespace).count
        let respond = respond
        return try await EditPrompts.write(instruction: instruction, context: context) { system, prompt in
            try await answer("write", words: words) { try await respond(system, prompt) }
        }
    }

    /// The model's answer within the time limit, logged by size and time (never by content).
    private func answer(_ task: String, words: Int,
                        _ work: @escaping @MainActor () async throws -> String) async throws -> String {
        let start = ContinuousClock.now
        let limit = timeout(words)
        do {
            let output = try await EditPrompts.race(within: limit, work)
            Self.log.notice("apple \(task, privacy: .public): \(Log.words(output)) words in \(Log.ms(ContinuousClock.now - start), privacy: .public) (input \(words) words)")
            return output
        } catch {
            let mapped = Self.editError(for: error)
            Self.log.notice("apple \(task, privacy: .public) failed after \(Log.ms(ContinuousClock.now - start), privacy: .public) (limit \(Log.ms(limit), privacy: .public), input \(words) words): \(Log.summary(error), privacy: .public) → \(String(describing: mapped), privacy: .public)")
            throw mapped
        }
    }
}
