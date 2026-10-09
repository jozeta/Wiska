import Core
import Foundation
import FoundationModels

/// Command mode: rewrites the selected text following a spoken instruction, on-device.
@MainActor
public final class FoundationModelsEditor: TextEditor {
    /// The on-device model's context is about 4,096 tokens; leave room for the answer.
    public static let maxWords = 2_000
    public static let timeout: Duration = .seconds(10)
    static let instructions = """
    You edit text. Apply the instruction to the text. \
    Keep the text's language unless the instruction asks for another. \
    Output only the edited text, without quotes or commentary.
    """

    public init() {}

    static func prompt(text: String, instruction: String) -> String {
        "Instruction: \(instruction)\n\nText:\n\(text)"
    }

    public func edit(_ text: String, instruction: String, language: Language?) async throws -> String {
        guard text.split(whereSeparator: \.isWhitespace).count <= Self.maxWords else { throw EditError.tooLong }
        guard case .available = SystemLanguageModel.default.availability else { throw EditError.unavailable }
        let prompt = Self.prompt(text: text, instruction: instruction)
        let work = Task { @MainActor in
            let session = LanguageModelSession(instructions: Self.instructions)
            return try await session.respond(to: prompt, options: GenerationOptions(temperature: 0)).content
        }
        let timer = Task {
            try? await Task.sleep(for: Self.timeout)
            work.cancel()
        }
        defer { timer.cancel() }
        let output: String
        do { output = try await work.value } catch { throw EditError.failed }
        let edited = CleanupPipeline.stripWrappingQuotes(output)
        guard !edited.isEmpty else { throw EditError.failed }
        return edited
    }
}
