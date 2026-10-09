import Core
import FoundationModels
import Testing
@testable import Cleanup

@MainActor
struct FoundationModelsRewriterTests {
    nonisolated static var modelAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    func polished(_ text: String) async throws -> String {
        let pipeline = CleanupPipeline(level: { .polished }, rewriter: FoundationModelsRewriter(),
                                       timeout: .seconds(10))
        return try await pipeline.clean(text, context: DictationContext())
    }

    static let fillerWords: Set<String> = ["um", "uh", "öh", "eh", "ehm", "alltså", "typ", "liksom"]

    @Test(.enabled(if: modelAvailable), .timeLimit(.minutes(2)),
          arguments: [
            "um so I was thinking we could uh maybe meet on on Tuesday no wait Wednesday at three you know",
            "öh kan du skicka eh rapporten till mig innan lunch alltså imorgon typ",
            "ehm jag tror liksom att vi borde öh vänta med beslutet tills nästa vecka",
            "hey Anna thanks for the update I'll uh I'll look at it tonight",
          ])
    func polishedRemovesFillers(input: String) async throws {
        let output = try await polished(input)
        let words = Set(CleanupGuard.words(output))
        #expect(words.isDisjoint(with: Self.fillerWords), "\(output)")
        #expect(!output.isEmpty)
    }

    @Test(.enabled(if: modelAvailable), .timeLimit(.minutes(1)))
    func questionsAreNotAnswered() async throws {
        let output = try await polished("what time is it in Tokyo right now")
        #expect(output.lowercased().contains("what time is it in tokyo"))
    }

    @Test(.enabled(if: modelAvailable), .timeLimit(.minutes(1)))
    func lightKeepsMaybe() async throws {
        let pipeline = CleanupPipeline(level: { .light }, rewriter: FoundationModelsRewriter(),
                                       timeout: .seconds(10))
        let output = try await pipeline.clean("um I think we could uh maybe meet on Wednesday at three",
                                              context: DictationContext())
        #expect(output.lowercased().contains("maybe"))
    }

    /// The pipeline's timeout relies on this: a cancelled call must stop, not keep the model busy.
    @Test(.enabled(if: modelAvailable), .timeLimit(.minutes(1)))
    func cancelledRewriteStopsPromptly() async throws {
        let rewriter = FoundationModelsRewriter()
        let long = String(repeating: "um so I think we should uh talk about the quarterly report ", count: 12)
        let start = ContinuousClock.now
        let task = Task { try await rewriter.rewrite(long, level: .polished, language: .english, style: .formal) }
        try await Task.sleep(for: .milliseconds(150))
        task.cancel()
        _ = try? await task.value
        #expect(ContinuousClock.now - start < .milliseconds(500))
    }

    @Test func prewarmKeepsOnlyTheCurrentLevel() {
        let rewriter = FoundationModelsRewriter()
        guard rewriter.isAvailable else { return }
        rewriter.prewarm(level: .light)
        rewriter.prewarm(level: .polished)
        #expect(rewriter.warmLevels == [.polished])
    }

    @Test func instructionsNameTheLanguageAndItsFillers() {
        let text = FoundationModelsRewriter.instructions(for: .light, language: .german, style: .formal)
        #expect(text.contains("Deutsch"))
        #expect(text.contains("ähm"))
    }

    @Test func reportsAvailability() {
        #expect(FoundationModelsRewriter().isAvailable == Self.modelAvailable)
    }

    @Test func instructionsCarryStyleAndNumbers() {
        let casual = FoundationModelsRewriter.instructions(for: .polished, language: .english, style: .casual)
        #expect(casual.contains("conversational"))
        #expect(casual.contains("digits"))
        let formal = FoundationModelsRewriter.instructions(for: .light, language: nil, style: .formal)
        #expect(formal.contains("complete sentences"))
        #expect(formal.contains("digits"))
    }

    @Test(.enabled(if: modelAvailable), .timeLimit(.minutes(1)))
    func spokenNumbersBecomeDigits() async throws {
        let output = try await polished("we could meet at three thirty on the fifth of May if that works for you")
        #expect(output.contains { $0.isNumber }, "\(output)")
    }
}
