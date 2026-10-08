import Testing
@testable import Cleanup

struct RuleCleanerTests {
    @Test(arguments: [
        ("um so I was uh thinking", "So I was thinking."),
        ("öh kan du eh skicka den", "Kan du skicka den."),
        ("the the cat", "The cat."),
        ("I had had enough", "I had had enough."),
        ("he said that that was fine", "He said that that was fine."),
        ("well, uh, fine", "Well, fine."),
        ("I like typ liksom alltså this", "I like typ liksom alltså this."),
        ("Tack för er hjälp", "Tack för er hjälp."),
        ("Already done!", "Already done!"),
        ("um", ""),
        ("", ""),
        ("  hello   world  ", "Hello world."),
    ])
    func cleans(input: String, expected: String) {
        #expect(RuleCleaner.clean(input) == expected)
    }
}
