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
                == "Rewrite in a formal, polite tone. Also: shorter")
        #expect(CommandResolver.resolve("Formal, then translate to Swedish", commands: [formal])
                == "Rewrite in a formal, polite tone. Also: translate to Swedish")
        // An instruction without a final full stop still reads as two sentences.
        let bare = SavedCommand(phrases: ["swedish"], instruction: "Translate to Swedish")
        #expect(CommandResolver.resolve("Swedish, keep it short.", commands: [bare])
                == "Translate to Swedish. Also: keep it short")
    }

    @Test func misheardAndLongestPhraseWin() {
        #expect(CommandResolver.resolve("formel", commands: [formal]) == "Rewrite in a formal, polite tone.")
        #expect(CommandResolver.resolve("Formal email, please", commands: [formal, formalEmail])
                == "Rewrite as a formal email. Also: please")
    }

    /// A command word that starts an ordinary instruction isn't the command: only the phrase
    /// alone, or followed by a comma or "and"/"then", is.
    @Test func phraseStartingASentenceIsNotACommand() {
        let fix = SavedCommand(phrases: ["fix"], instruction: "Fix spelling and grammar. Change nothing else.")
        #expect(CommandResolver.resolve("fix the second sentence and translate it", commands: [fix])
                == "fix the second sentence and translate it")
        #expect(CommandResolver.resolve("Formal email please", commands: [formal]) == "Formal email please")
        #expect(CommandResolver.resolve("fix och gör den kortare", commands: [fix])
                == "Fix spelling and grammar. Change nothing else. Also: gör den kortare")
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

/// Cleanup pass.
struct SavedCommandCleanupTests {
    /// Older or hand-edited files with missing keys still load.
    @Test func missingKeysDecodeWithDefaults() throws {
        let json = #"[{"phrases":["fix"]},{"instruction":"Be brief."}]"#
        let commands = try JSONDecoder().decode([SavedCommand].self, from: Data(json.utf8))
        #expect(commands.map(\.phrases) == [["fix"], []])
        #expect(commands.map(\.instruction) == ["", "Be brief."])
        #expect(commands[0].id != commands[1].id)
    }

    /// Try it: typing exactly a command's instruction text isn't "no command".
    @Test func matchedCommandIsFoundEvenWhenItsTextEqualsTheInput() {
        let command = SavedCommand(phrases: ["shorter"], instruction: "shorter")
        #expect(CommandResolver.matchedCommand("shorter", commands: [command]) == command)
        #expect(CommandResolver.matchedCommand("make it friendlier", commands: [command]) == nil)
    }
}
