import Core
import Testing
@testable import Cleanup

struct EmailLayoutTests {
    let english = Language.english.formatRules

    func layout(_ text: String, rules: FormatRules = Language.english.formatRules) -> [String] {
        EmailLayout.format([FormattedLine(text: text, isPlain: true)], rules: rules).map(\.text)
    }

    @Test func greetingAndSignOff() {
        #expect(layout("Hi Anna, thanks for the report. I'll read it tonight. Best regards, Johan.")
                == ["Hi Anna,", "", "Thanks for the report. I'll read it tonight.", "", "Best regards,", "Johan"])
    }

    @Test func greetingOnly() {
        #expect(layout("Hello team, the build is green.") == ["Hello team,", "", "The build is green."])
    }

    @Test func greetingWithoutCommaUsesCapitalisedName() {
        #expect(layout("Hi Anna Maria Svensson the meeting moved.")
                == ["Hi Anna Maria Svensson,", "", "The meeting moved."])
    }

    @Test func signOffWithoutName() {
        #expect(layout("Can you send the numbers? Thanks.") == ["Can you send the numbers?", "", "Thanks,"])
    }

    @Test func thanksForIsNotASignOff() {
        #expect(layout("I read it. Thanks for the update.") == ["I read it. Thanks for the update."])
    }

    @Test func greetingAloneIsUntouched() {
        #expect(layout("Hi Anna.") == ["Hi Anna."])
    }

    @Test func swedishEmail() {
        #expect(layout("Hej Erik, mötet är flyttat. Med vänliga hälsningar Johan.", rules: Language.swedish.formatRules)
                == ["Hej Erik,", "", "Mötet är flyttat.", "", "Med vänliga hälsningar,", "Johan"])
    }

    @Test func formattedLinesStayNotPlain() {
        let lines = EmailLayout.format([FormattedLine(text: "Hi Anna, see below.", isPlain: true),
                                        FormattedLine(text: "1. Eggs", isPlain: false)], rules: english)
        #expect(lines.map(\.isPlain) == [false, false, true, false])
    }

    @Test func greetingStopsBeforeI() {
        #expect(layout("Hi Anna I wanted to ask about the report.")
                == ["Hi Anna,", "", "I wanted to ask about the report."])
    }

    @Test func earlyCommaInASentenceIsNotAName() {
        #expect(layout("Hey can you, if possible, send the file today.")
                == ["Hey,", "", "Can you, if possible, send the file today."])
        #expect(layout("Hi everyone, the build is green.") == ["Hi everyone,", "", "The build is green."])
    }

    @Test func emailDictatedLineByLine() {
        let lines = EmailLayout.format([FormattedLine(text: "Hi Anna.", isPlain: true),
                                        FormattedLine(text: "Thanks for the help.", isPlain: true),
                                        FormattedLine(text: "Best regards Johan.", isPlain: true)], rules: english)
        #expect(lines.map(\.text) == ["Hi Anna,", "", "Thanks for the help.", "", "Best regards,", "Johan"])
        #expect(lines.map(\.isPlain) == [false, false, true, false, false, false])
    }

    /// A capitalised pronoun after a sign-off word is not a name ("Danke Ihnen" = "thank you").
    @Test func pronounIsNotASignOffName() {
        let german = layout("Ich komme morgen. Danke Ihnen.", rules: Language.german.formatRules)
        #expect(german == ["Ich komme morgen. Danke Ihnen."])
        let named = layout("Ich komme morgen. Viele Grüße Johan.", rules: Language.german.formatRules)
        #expect(named == ["Ich komme morgen.", "", "Viele Grüße,", "Johan"])
    }
}
