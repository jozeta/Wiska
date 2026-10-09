import Core

/// Command mode with a local model: the same prompts and post-processing as Apple's editor.
@MainActor
public final class LocalEditor: TextEditor {
    private let generator: any LocalGenerator
    private let timeout: @MainActor (Int) -> Duration

    public convenience init(generator: any LocalGenerator) {
        self.init(generator: generator, timeout: { EditPrompts.timeout(forWords: $0) })
    }

    init(generator: any LocalGenerator, timeout: @escaping @MainActor (Int) -> Duration) {
        self.generator = generator
        self.timeout = timeout
    }

    public var isAvailable: Bool { generator.isAvailable }

    public func edit(_ text: String, instruction: String, language: Language?) async throws -> String {
        let words = text.split(whereSeparator: \.isWhitespace).count
        guard words <= EditPrompts.maxWords else { throw EditError.tooLong }
        let output = try await answer(system: EditPrompts.instructions,
                                      prompt: EditPrompts.prompt(text: text, instruction: instruction),
                                      words: words, maxTokens: min(2_048, words * 3 + 128))
        return try EditPrompts.cleanEdited(original: text, output: output)
    }

    public func write(instruction: String, context: String?, language: Language?) async throws -> String {
        let words = (instruction + " " + (context ?? "")).split(whereSeparator: \.isWhitespace).count
        let output = try await answer(system: EditPrompts.writeInstructions,
                                      prompt: EditPrompts.writePrompt(instruction: instruction, context: context),
                                      words: words, maxTokens: 512)
        return try EditPrompts.cleanWritten(output, context: context)
    }

    private func answer(system: String, prompt: String, words: Int, maxTokens: Int) async throws -> String {
        guard generator.isAvailable else { throw EditError.unavailable }
        let generator = generator
        do {
            let raw = try await EditPrompts.race(within: timeout(words)) {
                try await generator.generate(system: system, prompt: prompt, maxTokens: maxTokens)
            }
            return LocalOutput.clean(raw)
        } catch is CancellationError {
            throw CancellationError()   // cancelled stays cancelled: no retry on Apple
        } catch {
            throw EditError.failed   // load errors, timeouts: retrying on Apple may help
        }
    }
}
