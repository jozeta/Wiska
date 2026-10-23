import Core
import Foundation
import FoundationModels

/// Cleanup with Apple's on-device language model (Apple Intelligence).
@MainActor
public final class FoundationModelsRewriter: TextRewriter {
    /// One session warmed at fn press, used by the first segment whose instructions it matches.
    private var warm: (instructions: String, session: LanguageModelSession)?

    public init() {}

    /// The instructions the warmed session was made with (tests).
    var warmInstructions: String? { warm?.instructions }

    public var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    public func prewarm(level: CleanupLevel, grammar: Bool) {
        prewarm(level: level, language: nil, style: .formal, grammar: grammar)
    }

    /// Warms a session for the dictation's likely language and style: one with any other
    /// instructions would never be used, so it's let go.
    public func prewarm(level: CleanupLevel, language: Language?, style: WritingStyle, grammar: Bool) {
        guard level != .off, isAvailable else {
            warm = nil
            return
        }
        let instructions = Self.instructions(level, language, style, grammar)
        guard warm?.instructions != instructions else { return }
        let session = LanguageModelSession(instructions: instructions)
        session.prewarm()
        warm = (instructions, session)
    }

    public func rewrite(_ text: String, level: CleanupLevel, language: Language?,
                        style: WritingStyle, grammar: Bool) async throws -> String {
        // A session keeps conversation history, so each segment gets a fresh one (the warmed
        // session is used once, by the first segment it was made for).
        let instructions = Self.instructions(level, language, style, grammar)
        let session: LanguageModelSession
        if let warm, warm.instructions == instructions {
            session = warm.session
            self.warm = nil
        } else {
            session = LanguageModelSession(instructions: instructions)
        }
        let response = try await session.respond(to: text, options: GenerationOptions(temperature: 0))
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Without the IT-term line: Apple's model copies the term list into text that never had it.
    static func instructions(_ level: CleanupLevel, _ language: Language?, _ style: WritingStyle, _ grammar: Bool) -> String {
        CleanupPrompts.instructions(for: level, language: language, style: style, grammar: grammar, itTerms: false)
    }
}
