import Core
import Foundation
import FoundationModels

/// Cleanup with Apple's on-device language model (Apple Intelligence).
@MainActor
public final class FoundationModelsRewriter: TextRewriter {
    private var warm: [CleanupLevel: LanguageModelSession] = [:]

    public init() {}

    var warmLevels: Set<CleanupLevel> { Set(warm.keys) }
    private(set) var warmGrammar = false

    public var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    public func prewarm(level: CleanupLevel, grammar: Bool) {
        // A session warmed for another level or grammar setting would never be used: let it go.
        warm = warm.filter { $0.key == level && grammar == warmGrammar }
        warmGrammar = grammar
        guard level != .off, isAvailable, warm[level] == nil else { return }
        let session = LanguageModelSession(instructions: CleanupPrompts.instructions(for: level, language: nil,
                                                                                     grammar: grammar))
        session.prewarm()
        warm[level] = session
    }

    public func rewrite(_ text: String, level: CleanupLevel, language: Language?,
                        style: WritingStyle, grammar: Bool) async throws -> String {
        // A session keeps conversation history, so each segment gets a fresh one (the prewarmed
        // session is used once, for the first segment). It was warmed with generic Formal
        // instructions for one grammar setting; anything else gets its own.
        let usable = language == nil && style == .formal && grammar == warmGrammar
        let session = usable ? warm.removeValue(forKey: level) : nil
        let fresh = session ?? LanguageModelSession(instructions: CleanupPrompts.instructions(
            for: level, language: language, style: style, grammar: grammar))
        let response = try await fresh.respond(to: text, options: GenerationOptions(temperature: 0))
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
