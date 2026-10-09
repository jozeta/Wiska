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
}
