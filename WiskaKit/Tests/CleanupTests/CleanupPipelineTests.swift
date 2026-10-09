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
    private(set) var languages: [Language?] = []
    private(set) var styles: [WritingStyle] = []
    private(set) var grammars: [Bool] = []
    private(set) var prewarmedGrammar: [Bool] = []

    func prewarm(level: CleanupLevel, grammar: Bool) { prewarmed.append(level); prewarmedGrammar.append(grammar) }

    func rewrite(_ text: String, level: CleanupLevel, language: Language?, style: WritingStyle,
                 grammar: Bool) async throws -> String {
        calls.append(text)
        languages.append(language)
        styles.append(style)
        grammars.append(grammar)
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
    @Test func grammarSettingReachesTheModel() async throws {
        let rewriter = FakeRewriter()
        let pipeline = CleanupPipeline(level: { .light }, rewriter: rewriter, grammar: { true })
        pipeline.prewarm()
        _ = try await pipeline.clean("he go to the store yesterday", context: DictationContext(language: .english))
        #expect(rewriter.grammars == [true])
        #expect(rewriter.prewarmedGrammar == [true])
    }

    let rewriter = FakeRewriter()

    func pipeline(_ level: CleanupLevel = .polished, timeout: Duration = .seconds(5)) -> CleanupPipeline {
        CleanupPipeline(level: { level }, rewriter: rewriter, timeout: timeout)
    }

    func clean(_ text: String, _ p: CleanupPipeline,
               context: DictationContext = DictationContext()) async throws -> String {
        try await p.clean(text, context: context)
    }

    static let signature = Snippet(phrases: ["insert my signature"], text: "Best regards,\nJohan")
    static let address = Snippet(phrases: ["insert my address"], text: "Storgatan 1, 111 22 Stockholm")

    func snippetPipeline(_ level: CleanupLevel = .polished, style: WritingStyle = .formal) -> CleanupPipeline {
        CleanupPipeline(level: { level }, rewriter: rewriter, style: { _ in style },
                        snippets: { [Self.signature, Self.address] }, timeout: .seconds(5))
    }

    @Test func snippetKeepsItsCapitalsInVeryCasual() async throws {
        rewriter.isAvailable = false
        let output = try await snippetPipeline(style: .veryCasual)
            .clean("um send it to insert my address", context: DictationContext(language: .english))
        #expect(output == "send it to Storgatan 1, 111 22 Stockholm")
    }

    @Test func snippetsWorkInCodeAndOff() async throws {
        #expect(try await snippetPipeline().clean("insert my signature", context: DictationContext(category: .code))
                == "Best regards,\nJohan")
        #expect(try await snippetPipeline(.off).clean("thanks insert my signature", context: DictationContext())
                == "thanks\nBest regards,\nJohan")
    }

    @Test func snippetSurvivesAModelThatDropsIt() async throws {
        rewriter.transform = { $0.replacingOccurrences(of: "wiskasnippet1", with: "") + "." }
        let output = try await snippetPipeline()
            .clean("please send the parcel to insert my address today", context: DictationContext(language: .english))
        #expect(output.contains("Storgatan 1, 111 22 Stockholm"), "\(output)")
    }

    @Test func signatureSnippetInEmail() async throws {
        rewriter.transform = { _ in "Hi Anna, the report is done." }
        let output = try await snippetPipeline()
            .clean("hi anna the report is done insert my signature",
                   context: DictationContext(language: .english, category: .email))
        #expect(output == "Hi Anna,\n\nThe report is done.\nBest regards,\nJohan")
    }

    func pipeline(style: WritingStyle, dictionary: PersonalDictionary = PersonalDictionary()) -> CleanupPipeline {
        CleanupPipeline(level: { .polished }, rewriter: rewriter, dictionary: { dictionary },
                        style: { _ in style }, timeout: .seconds(5))
    }

    @Test func theStyleReachesTheModelAndTheText() async throws {
        rewriter.transform = { _ in "hi Anna, I'll be there at 3." }
        let output = try await pipeline(style: .casual)
            .clean("hi anna i'll be there at three", context: DictationContext(category: .personal))
        #expect(output == "Hi Anna, I'll be there at 3")
        #expect(rewriter.styles == [.casual])
    }

    @Test func defaultStyleFollowsTheCategory() async throws {
        rewriter.transform = { _ in "see you at 3." }
        let p = CleanupPipeline(level: { .polished }, rewriter: rewriter, timeout: .seconds(5))
        #expect(try await p.clean("see you at three okay", context: DictationContext(category: .work)) == "See you at 3")
        #expect(try await p.clean("see you at three okay", context: DictationContext(category: .email)) == "See you at 3.")
    }

    @Test func codeSkipsTheModel() async throws {
        let output = try await pipeline(style: .formal)
            .clean("Git commit dash m fix.", context: DictationContext(category: .code))
        #expect(output == "git commit dash m fix")
        #expect(rewriter.calls.isEmpty)
    }

    @Test func codeKeepsDictionaryCapital() async throws {
        let output = try await pipeline(style: .formal, dictionary: PersonalDictionary(words: ["Wiska"]))
            .clean("Wiska build.", context: DictationContext(category: .code))
        #expect(output == "Wiska build")
    }

    @Test func offInCodeStaysRaw() async throws {
        let p = CleanupPipeline(level: { .off }, rewriter: rewriter, timeout: .seconds(5))
        #expect(try await p.clean("Git status.", context: DictationContext(category: .code)) == "Git status.")
    }

    @Test func offSkipsFormatting() async throws {
        let p = CleanupPipeline(level: { .off }, rewriter: rewriter, timeout: .seconds(5))
        #expect(try await p.clean("First eggs, second milk.", context: DictationContext()) == "First eggs, second milk.")
    }

    @Test func spokenListBecomesLines() async throws {
        rewriter.transform = { _ in "We need: first eggs, second milk, third bread." }
        let output = try await pipeline(style: .formal)
            .clean("we need first eggs second milk third bread", context: DictationContext(language: .english))
        #expect(output == "We need:\n1. Eggs\n2. Milk\n3. Bread")
    }

    @Test func emailCategoryLaysOutTheEmail() async throws {
        rewriter.transform = { _ in "Hi Anna, the report is done. Best regards, Johan." }
        let output = try await pipeline(style: .formal)
            .clean("hi anna the report is done best regards johan",
                   context: DictationContext(language: .english, category: .email))
        #expect(output == "Hi Anna,\n\nThe report is done.\n\nBest regards,\nJohan")
    }

    @Test func emailLayoutOnlyInEmail() async throws {
        rewriter.transform = { _ in "Hi Anna, the report is done." }
        let output = try await pipeline(style: .formal)
            .clean("hi anna the report is done", context: DictationContext(language: .english, category: .other))
        #expect(output == "Hi Anna, the report is done.")
    }

    @Test func ruleFallbackGetsTheStyleToo() async throws {
        rewriter.isAvailable = false
        let output = try await pipeline(style: .veryCasual)
            .clean("um Okay see you Tomorrow", context: DictationContext(language: .english))
        #expect(output == "okay see you tomorrow")
    }

    @Test func rulesFollowTheSpokenLanguage() async throws {
        rewriter.isAvailable = false   // rule cleanup only
        let german = DictationContext(language: .german, enabledLanguages: [.german, .english])
        #expect(try await pipeline().clean("äh das passt neue Zeile gut", context: german) == "Das passt.\nGut.")
    }

    @Test func unknownLanguageUsesTheTickedLanguagesRules() async throws {
        rewriter.isAvailable = false
        let context = DictationContext(language: nil, enabledLanguages: [.dutch])
        #expect(try await pipeline().clean("uh dat klopt", context: context) == "Dat klopt.")
    }

    @Test func rewriterIsToldTheLanguage() async throws {
        _ = try await clean("bonjour je pense que ça marche bien", pipeline(),
                            context: DictationContext(language: .french, enabledLanguages: [.french]))
        #expect(rewriter.languages == [.french])
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

    @Test func realQuotationsAreKept() async throws {
        rewriter.transform = { _ in "\"Hi,\" she said, \"see you soon.\"" }
        #expect(try await clean("hi she said see you soon", pipeline()) == "\"Hi,\" she said, \"see you soon.\"")
    }

    @Test func modelLineBreaksBecomeSpaces() async throws {
        rewriter.transform = { _ in "Thanks for the update.\nI'll look tonight." }
        #expect(try await clean("thanks for the update I'll look tonight", pipeline())
                == "Thanks for the update. I'll look tonight.")
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
