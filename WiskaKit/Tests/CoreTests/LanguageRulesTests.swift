import Testing
@testable import Core

struct LanguageRulesTests {
    @Test(arguments: Language.allCases)
    func everyLanguageHasFillersAndCommands(language: Language) {
        let rules = language.rules
        #expect(!rules.fillerSounds.isEmpty)
        #expect(!rules.newLine.isEmpty && !rules.newParagraph.isEmpty && !rules.scratchThat.isEmpty)
        #expect(!rules.questionWords.isEmpty && !rules.numberWords.isEmpty)
    }

    @Test func mergedRulesNeverRemoveAnOrdinaryWord() {
        for a in Language.allCases {
            for b in Language.allCases where a != b {
                let merged = LanguageRules.merged([a, b])
                for language in [a, b] {
                    let words = language.rules.questionWords.union(language.rules.numberWords)
                        .union(language.rules.determiners)
                    let clash = merged.fillerSounds.intersection(words)
                    #expect(clash.isEmpty, "\([a, b]) would remove \(clash) from \(language)")
                }
            }
        }
    }

    @Test func englishUmStaysWhenPortugueseMayBeSpoken() {
        #expect(!LanguageRules.merged([.english, .portuguese]).fillerSounds.contains("um"))
        #expect(Language.english.rules.fillerSounds.contains("um"))
    }

    @Test func englishAndSwedishAreTodaysLists() {
        let merged = LanguageRules.default
        #expect(merged.fillerSounds == ["um", "umm", "uh", "uhm", "erm", "ehm", "hmm", "öh", "eh", "äh", "ehh"])
        #expect(merged.newLine == ["new line", "ny rad"])
        #expect(merged.legitimateRepeats == ["had", "that"])
    }

    @Test func mergedIsTheUnion() {
        let rules = LanguageRules.merged([.german, .french])
        #expect(rules.fillerSounds.isSuperset(of: ["äh", "euh"]))
        #expect(rules.newLine.contains("neue zeile") && rules.newLine.contains("nouvelle ligne"))
    }
}
