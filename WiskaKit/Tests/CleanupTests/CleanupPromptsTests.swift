import Core
import Testing
@testable import Cleanup

struct CleanupPromptsTests {
    @Test func grammarLineOnlyWhenAsked() {
        for level in [CleanupLevel.light, .polished] {
            #expect(CleanupPrompts.instructions(for: level, language: .english, grammar: true).contains(CleanupPrompts.grammarLine))
            #expect(!CleanupPrompts.instructions(for: level, language: .english, grammar: false).contains(CleanupPrompts.grammarLine))
        }
        #expect(CleanupPrompts.grammarLine
                == "Fix grammar mistakes (verb forms, agreement, articles, word order); keep the meaning and otherwise the words.")
    }

    /// Light with grammar may change words to fix them; without, it may not change any.
    @Test func lightLetsGrammarChangeWords() {
        let strict = CleanupPrompts.instructions(for: .light, language: nil)
        #expect(strict.contains("Do not remove, add, reorder or change any other word"))
        let grammar = CleanupPrompts.instructions(for: .light, language: nil, grammar: true)
        #expect(!grammar.contains("Do not remove, add, reorder or change any other word"))
        #expect(grammar.contains("change words only to fix grammar"))
    }

    /// Swedish dictation may repair misheard IT terms; no other language gets the line.
    @Test func itTermsOnlyForSwedish() {
        for level in [CleanupLevel.light, .polished] {
            #expect(CleanupPrompts.instructions(for: level, language: .swedish).contains(TechTerms.promptLine))
            #expect(!CleanupPrompts.instructions(for: level, language: .english).contains(TechTerms.promptLine))
            #expect(!CleanupPrompts.instructions(for: level, language: nil).contains(TechTerms.promptLine))
        }
        #expect(CleanupPrompts.instructions(for: .light, language: .swedish).contains("and fixing a misheard IT term"))
    }
}
