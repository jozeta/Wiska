import Core
import Testing
@testable import Cleanup

struct ListFormatterTests {
    let english = Language.english.formatRules
    let swedish = Language.swedish.formatRules

    @Test func threeItems() {
        #expect(ListFormatter.format("First eggs, second milk, third bread.", rules: english)
                == ["1. Eggs", "2. Milk", "3. Bread"])
    }

    @Test func introBecomesAHeading() {
        #expect(ListFormatter.format("We need three things, first eggs, second milk and third bread.", rules: english)
                == ["We need three things:", "1. Eggs", "2. Milk", "3. Bread"])
    }

    @Test func swedishList() {
        #expect(ListFormatter.format("Att göra: för det första tvätta, för det andra handla.", rules: swedish)
                == ["Att göra:", "1. Tvätta", "2. Handla"])
    }

    @Test func oneMarkerIsProse() {
        #expect(ListFormatter.format("First I'll call you, then we decide.", rules: english) == nil)
    }

    @Test func markerMidClauseIsProse() {
        #expect(ListFormatter.format("It was the first time, the second time was better.", rules: english) == nil)
    }

    @Test func outOfOrderIsProse() {
        #expect(ListFormatter.format("First eggs, third bread, second milk.", rules: english) == nil)
    }

    @Test func noCommasNoList() {
        #expect(ListFormatter.format("First eggs second milk third bread.", rules: english) == nil)
    }

    @Test func questionMarkStays() {
        #expect(ListFormatter.format("Firstly, is it ready? Secondly, who pays?", rules: english)
                == ["1. Is it ready?", "2. Who pays?"])
    }

    @Test(arguments: [
        (Language.german, "Erstens Brot, zweitens Milch.", ["1. Brot", "2. Milch"]),
        (Language.french, "Premièrement du pain, deuxièmement du lait.", ["1. Du pain", "2. Du lait"]),
        (Language.spanish, "Primero pan, segundo leche.", ["1. Pan", "2. Leche"]),
        (Language.italian, "Primo pane, secondo latte.", ["1. Pane", "2. Latte"]),
        (Language.portuguese, "Primeiro pão, segundo leite.", ["1. Pão", "2. Leite"]),
        (Language.danish, "Først brød, for det andet mælk.", ["1. Brød", "2. Mælk"]),
        (Language.dutch, "Ten eerste brood, ten tweede melk.", ["1. Brood", "2. Melk"]),
    ])
    func otherLanguages(language: Language, input: String, expected: [String]) {
        #expect(ListFormatter.format(input, rules: language.formatRules) == expected)
    }
}
