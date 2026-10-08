import Core
import Testing
@testable import Cleanup

struct RewriteError: Error {}

@MainActor
final class FakeRewriter: TextRewriter {
    var isAvailable = true
    var delay: Duration = .zero
    var ignoresCancellation = false
    var error: Error?
    var transform: (String) -> String = { $0.uppercased() + "." }
    private(set) var calls: [String] = []
    private(set) var prewarmed: [CleanupLevel] = []

    func prewarm(level: CleanupLevel) { prewarmed.append(level) }

    func rewrite(_ text: String, level: CleanupLevel) async throws -> String {
        calls.append(text)
        if delay > .zero {
            if ignoresCancellation {
                let end = ContinuousClock.now + delay
                while ContinuousClock.now < end { try? await Task.sleep(for: .milliseconds(10)) }
            } else {
                try await Task.sleep(for: delay)
            }
        }
        if let error { throw error }
        return transform(text)
    }
}

@MainActor
struct CleanupPipelineTests {
    let rewriter = FakeRewriter()

    func pipeline(_ level: CleanupLevel = .polished, timeout: Duration = .seconds(5)) -> CleanupPipeline {
        CleanupPipeline(level: { level }, rewriter: rewriter, timeout: timeout)
    }

    func clean(_ text: String, _ p: CleanupPipeline) async throws -> String {
        try await p.clean(text, context: DictationContext())
    }

    @Test func offOnlyAppliesCommands() async throws {
        #expect(try await clean("hello um world new line bye", pipeline(.off)) == "hello um world\nbye")
        #expect(rewriter.calls.isEmpty)
    }

    @Test func segmentsAreCleanedSeparatelyAndBreaksKept() async throws {
        rewriter.transform = { $0 }   // identity is always accepted by the guard
        let out = try await clean("hello there my friend new paragraph and goodbye to you all", pipeline())
        #expect(rewriter.calls == ["hello there my friend", "and goodbye to you all"])
        #expect(out == "Hello there my friend.\n\nAnd goodbye to you all.")
    }

    @Test func shortSegmentSkipsTheModel() async throws {
        #expect(try await clean("ok um thanks", pipeline()) == "Ok thanks.")
        #expect(rewriter.calls.isEmpty)
    }

    @Test func unavailableModelFallsBackToRules() async throws {
        rewriter.isAvailable = false
        #expect(try await clean("um so we should ship it today", pipeline()) == "So we should ship it today.")
        #expect(rewriter.calls.isEmpty)
    }

    @Test func modelErrorFallsBackToRules() async throws {
        rewriter.error = RewriteError()
        #expect(try await clean("um so we should ship it today", pipeline()) == "So we should ship it today.")
    }

    @Test func guardRejectionFallsBackToRules() async throws {
        rewriter.transform = { _ in "It is currently 3 PM in Tokyo." }
        #expect(try await clean("what time is it in tokyo now", pipeline()) == "What time is it in tokyo now.")
    }

    @Test func acceptedRewriteIsUsed() async throws {
        rewriter.transform = { _ in "Kan du skicka rapporten?" }
        #expect(try await clean("öh kan du skicka rapporten", pipeline()) == "Kan du skicka rapporten?")
    }

    @Test func timeoutFallsBackToRules() async throws {
        rewriter.delay = .milliseconds(300)
        let start = ContinuousClock.now
        let out = try await clean("um so we should ship it today", pipeline(timeout: .milliseconds(50)))
        #expect(out == "So we should ship it today.")
        #expect(ContinuousClock.now - start < .milliseconds(250))
    }

    @Test func timeoutHoldsEvenIfRewriterIgnoresCancellation() async throws {
        rewriter.delay = .milliseconds(400)
        rewriter.ignoresCancellation = true
        let start = ContinuousClock.now
        let out = try await clean("um so we should ship it today", pipeline(timeout: .milliseconds(50)))
        #expect(out == "So we should ship it today.")
        #expect(ContinuousClock.now - start < .milliseconds(250))
    }

    @Test func segmentsAfterDeadlineUseRules() async throws {
        rewriter.transform = { $0 }
        rewriter.delay = .milliseconds(60)
        let out = try await clean(
            "first part of it here new line second part of it here new line third part of it here",
            pipeline(timeout: .milliseconds(90)))
        #expect(rewriter.calls.count <= 2)
        #expect(out.components(separatedBy: "\n").count == 3)
    }

    @Test func wrappingQuotesAreStripped() async throws {
        rewriter.transform = { "\"\($0).\"" }
        #expect(try await clean("hello there my friend", pipeline()) == "Hello there my friend.")
    }

    @Test func trailingCommandKeepsLineBreak() async throws {
        #expect(try await clean("thanks a lot new line", pipeline()) == "Thanks a lot.\n")
    }

    @Test func onlyScratchThatGivesEmptyText() async throws {
        #expect(try await clean("scratch that", pipeline()) == "")
    }

    @Test func prewarmPassesTheLevel() {
        pipeline(.light).prewarm()
        #expect(rewriter.prewarmed == [.light])
    }

    @Test func prewarmSkippedWhenOffOrUnavailable() {
        pipeline(.off).prewarm()
        rewriter.isAvailable = false
        pipeline(.polished).prewarm()
        #expect(rewriter.prewarmed.isEmpty)
    }

    @Test func defaultBudgetLeavesRoomForTailAndTranscription() {
        // Review I3: release→paste must stay < 1.5 s, so cleanup gets at most 1 s.
        #expect(CleanupPipeline.defaultTimeout == .milliseconds(1_000))
    }

    @Test func acceptedRewriteGetsCapitalAndTerminalPunctuation() async throws {
        // Review I5: the model sometimes omits punctuation.
        rewriter.transform = { _ in "hey Anna thanks for the update I'll look at it tonight" }
        let out = try await clean("hey Anna thanks for the update I'll uh I'll look at it tonight", pipeline())
        #expect(out == "Hey Anna thanks for the update I'll look at it tonight.")
    }
    func pipeline(_ level: CleanupLevel, dictionary: PersonalDictionary) -> CleanupPipeline {
        CleanupPipeline(level: { level }, rewriter: rewriter, dictionary: { dictionary }, timeout: .seconds(5))
    }

    let memory = PersonalDictionary(words: ["Kvarnholmen"],
                                    replacements: [Replacement(heard: "secure whisper", written: "SecureWispr")])

    @Test func dictionaryAppliesEvenWhenCleanupIsOff() async throws {
        let out = try await clean("um the Kvarnholman launch of secure whisper", pipeline(.off, dictionary: memory))
        #expect(out == "um the Kvarnholmen launch of SecureWispr")
    }

    @Test func modelSeesCorrectedText() async throws {
        rewriter.transform = { $0 }
        _ = try await clean("the Kvarnholman launch of secure whisper", pipeline(.polished, dictionary: memory))
        #expect(rewriter.calls == ["the Kvarnholmen launch of SecureWispr"])
    }

    @Test func dictionaryIsReappliedAfterTheModel() async throws {
        rewriter.transform = { _ in "The Kvarnholman launch of SecureWispr." }   // model "undid" a spelling
        let out = try await clean("the kvarnholmen launch of secure whisper", pipeline(.polished, dictionary: memory))
        #expect(out == "The Kvarnholmen launch of SecureWispr.")
    }

    @Test func pipelinePassesTheLexiconToTheCorrector() async throws {
        let p = CleanupPipeline(level: { .off }, rewriter: rewriter,
                                dictionary: { PersonalDictionary(words: ["Klara", "Kvarnholmen"]) },
                                isKnownWord: { ["klara", "det", "kan", "vi"].contains($0.lowercased()) },
                                timeout: .seconds(5))
        #expect(try await clean("vi kan klara det på Kvarnholman", p) == "vi kan klara det på Kvarnholmen")
    }
}
