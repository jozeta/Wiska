import Core

/// Command mode with a local model: the same prompts and post-processing as Apple's editor.
@MainActor
public final class LocalEditor: TextEditor {
    private static let log = Log.logger("Cleanup")
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
        guard words <= EditPrompts.maxWords else {
            Self.log.notice("gemma edit: selection too long (\(words) words, limit \(EditPrompts.maxWords))")
            throw EditError.tooLong
        }
        let output = try await answer("edit", system: EditPrompts.instructions,
                                      prompt: EditPrompts.prompt(text: text, instruction: instruction),
                                      words: words, maxTokens: min(2_048, words * 3 + 128))
        return try EditPrompts.cleanEdited(original: text, output: output)
    }

    public func write(instruction: String, context: String?, language: Language?) async throws -> String {
        let words = (instruction + " " + (context ?? "")).split(whereSeparator: \.isWhitespace).count
        return try await EditPrompts.write(instruction: instruction, context: context) { system, prompt in
            try await answer("write", system: system, prompt: prompt, words: words, maxTokens: 512)
        }
    }

    private func answer(_ task: String, system: String, prompt: String, words: Int, maxTokens: Int) async throws -> String {
        guard generator.isAvailable else {
            Self.log.notice("gemma \(task, privacy: .public): model not available")
            throw EditError.unavailable
        }
        let generator = generator
        let start = ContinuousClock.now
        let limit = timeout(words)
        do {
            let raw = try await EditPrompts.race(within: limit) {
                try await generator.generate(system: system, prompt: prompt, maxTokens: maxTokens)
            }
            let output = LocalOutput.clean(raw)
            Self.log.notice("gemma \(task, privacy: .public): \(Log.words(output)) words in \(Log.ms(ContinuousClock.now - start), privacy: .public) (input \(words) words)")
            return output
        } catch is CancellationError {
            throw CancellationError()   // cancelled stays cancelled: no retry on Apple
        } catch {
            // Load errors, timeouts: retrying on Apple may help.
            Self.log.notice("gemma \(task, privacy: .public) failed after \(Log.ms(ContinuousClock.now - start), privacy: .public) (limit \(Log.ms(limit), privacy: .public), input \(words) words): \(Log.summary(error), privacy: .public)")
            throw EditError.failed
        }
    }
}
