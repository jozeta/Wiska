import Core
import Testing
@testable import Cleanup

struct StyleFinisherTests {
    let dictionary = PersonalDictionary(words: ["Wiska", "macOS"])

    func finish(_ text: String, _ style: WritingStyle) -> String {
        StyleFinisher.finish(text, style: style, dictionary: dictionary)
    }

    @Test func formalFinishesTheSentence() {
        #expect(finish("see you at 3", .formal) == "See you at 3.")
        #expect(finish("Is it ready?", .formal) == "Is it ready?")
        #expect(finish("He said \"see you soon.\"", .formal) == "He said \"see you soon.\"")
    }

    @Test func casualDropsOnlyTheFinalFullStop() {
        #expect(finish("Hi Anna, I'll be there at 3.", .casual) == "Hi Anna, I'll be there at 3")
        #expect(finish("Done. See you", .casual) == "Done. See you")
        #expect(finish("Really?", .casual) == "Really?")
        #expect(finish("Wow!", .casual) == "Wow!")
        #expect(finish("Well…", .casual) == "Well…")
    }

    @Test func veryCasualLowerCases() {
        #expect(finish("Hi Anna, I'll be there at 3.", .veryCasual) == "hi anna, I'll be there at 3")
    }

    @Test func veryCasualKeepsIAndDictionaryWords() {
        #expect(finish("I think Wiska runs on MacOS. I'm sure.", .veryCasual) == "I think Wiska runs on macOS. I'm sure")
    }

    @Test func codeSafeRemovesTheEnginesSentenceShape() {
        #expect(StyleFinisher.codeSafe("Git status.", dictionary: dictionary) == "git status")
        #expect(StyleFinisher.codeSafe("Wiska build.", dictionary: dictionary) == "Wiska build")
        #expect(StyleFinisher.codeSafe("Ls -la", dictionary: dictionary) == "ls -la")
        #expect(StyleFinisher.codeSafe("Echo done.\nExit.", dictionary: dictionary) == "echo done\nexit")
    }

    @Test func veryCasualKeepsAcronymsAndMultiWordEntries() {
        let dictionary = PersonalDictionary(words: ["New York", "Wiska"])
        let output = StyleFinisher.finish("Flying to New York with NASA and the EU team.", style: .veryCasual,
                                          dictionary: dictionary)
        #expect(output == "flying to New York with NASA and the EU team")
    }
}
