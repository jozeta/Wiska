import Testing
@testable import Cleanup

struct VoiceCommandsTests {
    @Test(arguments: [
        ("hello new line world", "hello\nworld"),
        ("Hello. New line. World", "Hello.\nWorld"),
        ("Hej, ny rad, hur mår du", "Hej\nhur mår du"),
        ("first nytt stycke second", "first\n\nsecond"),
        ("First. New paragraph. Second", "First.\n\nSecond"),
        ("meet tuesday at three scratch that meet wednesday at four", "meet wednesday at four"),
        ("möt på tisdag, stryk det, möt på onsdag", "möt på onsdag"),
        ("a scratch that b. Stryk det. c", "c"),
        ("scratch that", ""),
        ("hello new line", "hello\n"),
        ("the newline character", "the newline character"),
        ("no commands here", "no commands here"),
    ])
    func appliesCommands(input: String, expected: String) {
        #expect(VoiceCommands.apply(input) == expected)
    }

    @Test func scratchAppliesBeforeLineCommands() {
        #expect(VoiceCommands.apply("one new line two scratch that three new line four") == "three\nfour")
    }
}
