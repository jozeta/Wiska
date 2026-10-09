import Foundation
import Testing
@testable import Core

struct SavedCommandTests {
    let formal = SavedCommand(phrases: ["formal"], instruction: "Rewrite in a formal, polite tone.")
    let formalEmail = SavedCommand(phrases: ["formal email"], instruction: "Rewrite as a formal email.")

    @Test func problemsExplainWhyACommandCantWork() {
        #expect(SavedCommand(phrases: [" ", ""], instruction: "x").problems == [.noPhrase])
        #expect(SavedCommand(phrases: ["fix"], instruction: "  ").problems == [.noInstruction])
        #expect(SavedCommand(phrases: ["fix"], instruction: "Fix it.").problems.isEmpty)   // one word is fine
        #expect(SavedCommand(phrases: [" fix ", ""], instruction: "x").spokenPhrases == ["fix"])
    }

    @Test func roundTripsAsJSON() throws {
        let data = try JSONEncoder().encode([formal])
        #expect(try JSONDecoder().decode([SavedCommand].self, from: data) == [formal])
    }

    @Test func phraseAloneIsTheInstruction() {
        #expect(CommandResolver.resolve("Formal.", commands: [formal]) == "Rewrite in a formal, polite tone.")
    }

    @Test func extraWordsAreAppended() {
        #expect(CommandResolver.resolve("formal and shorter", commands: [formal])
                == "Rewrite in a formal, polite tone. Also: and shorter")
        // An instruction without a final full stop still reads as two sentences.
        let bare = SavedCommand(phrases: ["swedish"], instruction: "Translate to Swedish")
        #expect(CommandResolver.resolve("Swedish, keep it short.", commands: [bare])
                == "Translate to Swedish. Also: keep it short")
    }

    @Test func misheardAndLongestPhraseWin() {
        #expect(CommandResolver.resolve("formel", commands: [formal]) == "Rewrite in a formal, polite tone.")
        #expect(CommandResolver.resolve("Formal email please", commands: [formal, formalEmail])
                == "Rewrite as a formal email. Also: please")
    }

    @Test func noMatchKeepsTheSpokenWords() {
        #expect(CommandResolver.resolve("make this friendlier", commands: [formal]) == "make this friendlier")
        #expect(CommandResolver.resolve("make it formal", commands: [formal]) == "make it formal")   // only at the start
        #expect(CommandResolver.resolve("formal", commands: []) == "formal")
        let empty = SavedCommand(phrases: ["formal"], instruction: " ")
        #expect(CommandResolver.resolve("formal", commands: [empty]) == "formal")
    }

    @Test func defaultsAreTheShippedFour() {
        let pairs = CommandResolver.defaults.map { ($0.phrases, $0.instruction) }
        #expect(pairs.map(\.0) == [["fix"], ["formal"], ["shorter"], ["bullets"]])
        #expect(pairs.map(\.1) == ["Fix spelling and grammar. Change nothing else.",
                                   "Rewrite in a formal, polite tone.",
                                   "Make it shorter. Keep the meaning.",
                                   "Turn it into a bulleted list."])
    }
}
