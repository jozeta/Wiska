import Core
import Testing
@testable import Cleanup

/// A model that wants little time (like Gemma's 2.5 s for a dictation) but is slow.
@MainActor
private final class HurriedRewriter: TextRewriter {
    let inner = FakeRewriter()
    var isAvailable: Bool { true }
    var preferredTimeout: Duration? { .milliseconds(50) }
    func prewarm(level: CleanupLevel, grammar: Bool) {}
    func rewrite(_ text: String, level: CleanupLevel, language: Language?, style: WritingStyle,
                 grammar: Bool) async throws -> String {
        try await Task.sleep(for: .milliseconds(200))
        return try await inner.rewrite(text, level: level, language: language, style: style, grammar: grammar)
    }
}

/// Audio files and meetings: what was said is text, never a command.
@MainActor
struct RecordingCleanupTests {
    @Test func aRecordingKeepsCommandWordsAsWords() async throws {
        let rewriter = FakeRewriter()
        rewriter.transform = { $0 }
        let pipeline = CleanupPipeline(level: { .light }, rewriter: rewriter)
        var context = DictationContext(language: .english)
        context.isRecording = true
        let output = try await pipeline.clean("we should scratch that plan and start a new line of work, comma included",
                                              context: context)
        #expect(output.contains("scratch that plan"))
        #expect(output.contains("comma included"))
        #expect(!output.contains("\n"))
    }

    @Test func aDictationStillObeysThem() async throws {
        let rewriter = FakeRewriter()
        rewriter.transform = { $0 }
        let pipeline = CleanupPipeline(level: { .light }, rewriter: rewriter)
        let output = try await pipeline.clean("old idea scratch that new idea here today",
                                              context: DictationContext(language: .english))
        #expect(!output.contains("old idea"))
    }

    /// The file pipeline's long limit wins over a model's short preference.
    @Test func theLongerTimeLimitWins() async throws {
        let hurried = HurriedRewriter()
        hurried.inner.transform = { $0 + " (model)" }
        let pipeline = CleanupPipeline(level: { .light }, rewriter: hurried, timeout: .seconds(5))
        let output = try await pipeline.clean("this is a sentence from a recording", context: DictationContext(language: .english))
        #expect(output.contains("(model)"))
    }
}
