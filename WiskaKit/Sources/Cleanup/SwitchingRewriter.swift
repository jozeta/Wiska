import Core

/// Cleanup with the chosen language model, or the other one when it's unavailable or fails.
@MainActor
public final class SwitchingRewriter: TextRewriter {
    private static let log = Log.logger("Cleanup")
    private let choice: @MainActor () -> LanguageModelChoice
    private let apple: any TextRewriter
    private let local: any TextRewriter

    public init(choice: @escaping @MainActor () -> LanguageModelChoice, apple: any TextRewriter, local: any TextRewriter) {
        self.choice = choice
        self.apple = apple
        self.local = local
    }

    /// The available models, the chosen one first.
    private var models: [(name: String, model: any TextRewriter)] {
        let all: [(name: String, model: any TextRewriter)] = choice() == .gemma
            ? [("gemma", local), ("apple", apple)] : [("apple", apple), ("gemma", local)]
        return all.filter { $0.model.isAvailable }
    }

    public var isAvailable: Bool { !models.isEmpty }
    public var preferredTimeout: Duration? { models.first?.model.preferredTimeout }

    public func prewarm(level: CleanupLevel, grammar: Bool) {
        models.first?.model.prewarm(level: level, grammar: grammar)
    }

    public func rewrite(_ text: String, level: CleanupLevel, language: Language?, style: WritingStyle,
                        grammar: Bool) async throws -> String {
        let models = models
        guard let first = models.first else { throw EditError.unavailable }
        let start = ContinuousClock.now
        do {
            let output = try await first.model.rewrite(text, level: level, language: language, style: style, grammar: grammar)
            Self.log.info("cleanup by \(first.name, privacy: .public) in \((ContinuousClock.now - start).formatted(.units(allowed: [.milliseconds])), privacy: .public)")
            return output
        } catch {
            guard models.count > 1, !(error is CancellationError) else { throw error }
            Self.log.notice("cleanup by \(first.name, privacy: .public) failed (\(String(describing: type(of: error)), privacy: .public)); trying \(models[1].name, privacy: .public)")
            return try await models[1].model.rewrite(text, level: level, language: language, style: style, grammar: grammar)
        }
    }
}
