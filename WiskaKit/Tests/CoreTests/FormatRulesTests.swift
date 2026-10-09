import Testing
@testable import Core

struct FormatRulesTests {
    @Test(arguments: Language.allCases)
    func everyLanguageHasFormattingWords(language: Language) {
        let rules = language.formatRules
        #expect(rules.listMarkers.count == 10)
        let emptyMarkers = rules.listMarkers.filter(\.isEmpty)
        #expect(emptyMarkers.isEmpty)
        #expect(!rules.greetings.isEmpty)
        #expect(!rules.signOffs.isEmpty)
        #expect(!rules.conjunctions.isEmpty)
        #expect(!rules.numberExtras.isEmpty)
    }

    @Test(arguments: Language.allCases)
    func entriesAreLowerCase(language: Language) {
        let rules = language.formatRules
        let words = rules.listMarkers.flatMap { $0 } + rules.greetings.map { $0.joined(separator: " ") }
            + rules.signOffs.map { $0.joined(separator: " ") } + Array(rules.conjunctions) + Array(rules.numberExtras)
        let upper = words.filter { $0 != $0.lowercased() }
        #expect(upper.isEmpty)
    }

    @Test func ordinalsAndPercentAreNumberWords() {
        #expect(Language.english.rules.numberWords.isSuperset(of: ["fifth", "first", "percent"]))
        #expect(Language.swedish.rules.numberWords.isSuperset(of: ["femte", "procent"]))
        #expect(!Language.english.rules.numberWords.contains("may"))
    }

    @Test func mergedKeepsItemOrder() {
        let merged = FormatRules.merged([.english, .swedish])
        #expect(merged.listMarkers[0].contains("first"))
        #expect(merged.listMarkers[0].contains("först"))
        #expect(merged.listMarkers[1].contains("second"))
        #expect(merged.greetings.contains(["hej"]))
    }

    @Test(arguments: Language.allCases)
    func everyLanguageHasInsertWords(language: Language) {
        #expect(!language.formatRules.insertWords.isEmpty)
        #expect(!language.formatRules.possessives.isEmpty)
    }

    @Test func insertWordsMerge() {
        let merged = FormatRules.merged([.english, .swedish])
        #expect(merged.insertWords.contains(["insert"]))
        #expect(merged.insertWords.contains(["infoga"]))
        #expect(merged.possessives.contains(["min"]))
    }
}
