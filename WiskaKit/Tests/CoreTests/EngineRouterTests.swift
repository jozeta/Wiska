import Foundation
import Testing
@testable import Core

struct EngineRouterTests {
    private func engines(en: SpeechEngine, sv: SpeechEngine) -> (Language) -> SpeechEngine {
        { $0 == .english ? en : sv }
    }

    @Test func fixedLanguageUsesItsEngine() {
        let mixed = engines(en: .parakeet, sv: .apple)
        #expect(EngineRouter.plan(choice: .fixed(.english), engines: mixed, parakeetReady: true) == .single(.parakeet))
        #expect(EngineRouter.plan(choice: .fixed(.swedish), engines: mixed, parakeetReady: true) == .single(.apple))
    }

    @Test func parakeetNotReadyFallsBackToApple() {
        let mixed = engines(en: .parakeet, sv: .apple)
        #expect(EngineRouter.plan(choice: .fixed(.english), engines: mixed, parakeetReady: false) == .single(.apple))
        #expect(EngineRouter.plan(choice: .automatic, engines: mixed, parakeetReady: false) == .single(.apple))
        #expect(EngineRouter.plan(choice: .automatic, engines: engines(en: .parakeet, sv: .parakeet),
                                  parakeetReady: false) == .single(.apple))
    }

    @Test func automaticWithOneEngineUsesIt() {
        #expect(EngineRouter.plan(choice: .automatic, engines: engines(en: .apple, sv: .apple),
                                  parakeetReady: true) == .single(.apple))
        #expect(EngineRouter.plan(choice: .automatic, engines: engines(en: .parakeet, sv: .parakeet),
                                  parakeetReady: true) == .single(.parakeet))
    }

    @Test func automaticWithMixedEnginesIsHybrid() {
        #expect(EngineRouter.plan(choice: .automatic, engines: engines(en: .parakeet, sv: .apple),
                                  parakeetReady: true) == .hybrid(apple: [.swedish]))
        #expect(EngineRouter.plan(choice: .automatic, engines: engines(en: .apple, sv: .parakeet),
                                  parakeetReady: true) == .hybrid(apple: [.english]))
    }

    @Test func transcriptEngineDefaultsToNil() {
        #expect(Transcript(text: "a", locale: .current).engine == nil)
        #expect(Transcript(text: "a", locale: .current, engine: .parakeet).engine == .parakeet)
    }

    @Test func languageChoiceMattersUnlessEveryLanguageUsesParakeet() {
        #expect(!EngineRouter.languageChoiceMatters(engines: engines(en: .parakeet, sv: .parakeet), parakeetReady: true))
        #expect(EngineRouter.languageChoiceMatters(engines: engines(en: .parakeet, sv: .parakeet), parakeetReady: false))
        #expect(EngineRouter.languageChoiceMatters(engines: engines(en: .parakeet, sv: .apple), parakeetReady: true))
    }
}
