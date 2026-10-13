import Core

/// Command mode with the chosen language model, or the other one when it's unavailable or fails.
@MainActor
public final class SwitchingEditor: TextEditor {
    private static let log = Log.logger("Cleanup")
    private let choice: @MainActor () -> LanguageModelChoice
    private let apple: any TextEditor
    private let local: any TextEditor
    private let appleAvailable: @MainActor () -> Bool
    private let localAvailable: @MainActor () -> Bool

    public init(choice: @escaping @MainActor () -> LanguageModelChoice, apple: any TextEditor, local: any TextEditor,
                appleAvailable: @escaping @MainActor () -> Bool, localAvailable: @escaping @MainActor () -> Bool) {
        self.choice = choice
        self.apple = apple
        self.local = local
        self.appleAvailable = appleAvailable
        self.localAvailable = localAvailable
    }

    private var models: [(name: String, editor: any TextEditor)] {
        let apple: (name: String, editor: any TextEditor)? = appleAvailable() ? ("apple", self.apple) : nil
        let local: (name: String, editor: any TextEditor)? = localAvailable() ? ("gemma", self.local) : nil
        return (choice() == .gemma ? [local, apple] : [apple, local]).compactMap { $0 }
    }

    public func edit(_ text: String, instruction: String, language: Language?) async throws -> String {
        try await withFallback { try await $0.edit(text, instruction: instruction, language: language) }
    }

    public func write(instruction: String, context: String?, language: Language?) async throws -> String {
        try await withFallback { try await $0.write(instruction: instruction, context: context, language: language) }
    }

    /// A selection too long for one model is too long for both; anything else may work on the other.
    private func withFallback(_ run: @MainActor (any TextEditor) async throws -> String) async throws -> String {
        let models = models
        guard let first = models.first else {
            Self.log.notice("command: no language model available")
            throw EditError.unavailable
        }
        do {
            return try await run(first.editor)
        } catch EditError.tooLong {
            throw EditError.tooLong
        } catch {
            guard models.count > 1 else { throw error }
            Self.log.notice("command by \(first.name, privacy: .public) failed (\(Log.summary(error), privacy: .public)); trying \(models[1].name, privacy: .public)")
            return try await run(models[1].editor)
        }
    }
}
