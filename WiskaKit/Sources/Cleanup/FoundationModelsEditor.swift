import Core
import Foundation
import FoundationModels

/// Command mode: rewrites the selected text following a spoken instruction, on-device.
@MainActor
public final class FoundationModelsEditor: TextEditor {

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
        guard words <= EditPrompts.maxWords else { throw EditError.tooLong }
        guard isAvailable() else { throw EditError.unavailable }
        let respond = respond
        let output: String
        do {
            output = try await EditPrompts.race(within: timeout(words)) {
                try await respond(EditPrompts.instructions, EditPrompts.prompt(text: text, instruction: instruction))
            }
        } catch {
            throw Self.editError(for: error)
        }
        return try EditPrompts.cleanEdited(original: text, output: output)
    }

    public func write(instruction: String, context: String?, language: Language?) async throws -> String {
        guard isAvailable() else { throw EditError.unavailable }
        let words = (instruction + " " + (context ?? "")).split(whereSeparator: \.isWhitespace).count
        let respond = respond
        let output: String
        do {
            output = try await EditPrompts.race(within: timeout(words)) {
                try await respond(EditPrompts.writeInstructions,
                                  EditPrompts.writePrompt(instruction: instruction, context: context))
            }
        } catch {
            throw Self.editError(for: error)
        }
        return try EditPrompts.cleanWritten(output, context: context)
    }
}
