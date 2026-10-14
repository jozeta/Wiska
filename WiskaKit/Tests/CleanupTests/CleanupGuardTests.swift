import Core
import Testing
@testable import Cleanup

struct CleanupGuardTests {
    let rambling = "um so I was thinking we could uh maybe meet on on Tuesday no wait Wednesday at three you know"
    let corrected = "I was thinking we could meet on Wednesday at three."

    @Test func acceptsPolishedSelfCorrection() {
        #expect(CleanupGuard.check(original: rambling, cleaned: corrected, level: .polished) == .accept)
    }

    @Test func rejectsAnAnswer() {
        let verdict = CleanupGuard.check(original: "what time is it in tokyo right now",
                                         cleaned: "It is currently 3 PM in Tokyo.", level: .polished)
        #expect(verdict != .accept)
    }

    @Test func rejectsAPreamble() {
        let verdict = CleanupGuard.check(original: "hello there",
                                         cleaned: "Here is the cleaned text: Hello there.", level: .light)
        #expect(verdict != .accept)
    }

    @Test func lightRejectsADroppedClauseThatPolishedAllows() {
        let original = "send the report to Anna and also copy Erik on it please"
        let cleaned = "Send the report to Anna."
        #expect(CleanupGuard.check(original: original, cleaned: cleaned, level: .light) != .accept)
        #expect(CleanupGuard.check(original: original, cleaned: cleaned, level: .polished) == .accept)
    }

    @Test func lightMustKeepWordsOnlyPolishedMayTreatAsFillers() {
        let original = "can you tell me where the keys are"
        let cleaned = "Can tell me where the keys are?"
        #expect(CleanupGuard.check(original: original, cleaned: cleaned, level: .light) != .accept)
        #expect(CleanupGuard.check(original: "so like you know we should go",
                                   cleaned: "So we should go.", level: .polished) == .accept)
    }

    @Test func rejectsEmpty() {
        #expect(CleanupGuard.check(original: "hello there", cleaned: "  ", level: .polished) != .accept)
    }

    @Test func acceptsSwedishFillerRemoval() {
        #expect(CleanupGuard.check(
            original: "öh kan du skicka eh rapporten till mig innan lunch alltså imorgon typ",
            cleaned: "Kan du skicka rapporten till mig innan lunch imorgon?", level: .light) == .accept)
    }

    @Test func acceptsSwedishSpellingNormalisation() {
        // Review I4: "imorgon" → "i morgon" is the same words.
        #expect(CleanupGuard.check(original: "ska vi ses imorgon på kontoret",
                                   cleaned: "Ska vi ses i morgon på kontoret?", level: .light) == .accept)
    }

    @Test func acceptsSpokenNumbersWrittenAsDigits() {
        #expect(CleanupGuard.check(original: "let's meet at two thirty pm",
                                   cleaned: "Let's meet at 2:30 PM.", level: .light) == .accept)
    }

    @Test func rejectsAnAnswerWithDigitsWhenNoNumberWasSpoken() {
        // Real model output seen in Task-4 tests after the I4 change: it answered the question.
        #expect(CleanupGuard.check(original: "what time is it in tokyo right now",
                                   cleaned: "It is 3:15 pm in Tokyo right now.", level: .polished) != .accept)
    }

    @Test func rejectsAQuestionTurnedIntoAStatement() {
        #expect(CleanupGuard.check(original: "vad är klockan i tokyo just nu",
                                   cleaned: "Klockan är sent i Tokyo just nu.", level: .polished) != .accept)
    }

    @Test func keepsAQuestionAsAQuestion() {
        #expect(CleanupGuard.check(original: "um what time is it in tokyo right now",
                                   cleaned: "What time is it in Tokyo right now?", level: .polished) == .accept)
    }

    @Test func acceptsDatesAsDigits() {
        #expect(CleanupGuard.check(original: "we meet on the fifth of may", cleaned: "We meet on 5 May.",
                                   level: .polished, rules: Language.english.rules) == .accept)
        #expect(CleanupGuard.check(original: "vi ses den femte maj", cleaned: "Vi ses den 5 maj.",
                                   level: .polished, rules: Language.swedish.rules) == .accept)
        #expect(CleanupGuard.check(original: "we meet on the fifth of may", cleaned: "We meet on the 5th of May.",
                                   level: .light, rules: Language.english.rules) == .accept)
    }

    @Test func acceptsPercentAndTimeAtLight() {
        #expect(CleanupGuard.check(original: "it went up twenty five percent", cleaned: "It went up 25%.",
                                   level: .polished, rules: Language.english.rules) == .accept)
        #expect(CleanupGuard.check(original: "see you at three thirty", cleaned: "See you at 3:30.",
                                   level: .light, rules: Language.english.rules) == .accept)
    }

    @Test func digitsWithoutSpokenNumbersStillRejected() {
        #expect(CleanupGuard.check(original: "you may want to check the clock in tokyo",
                                   cleaned: "It is 3:15 pm in Tokyo.", level: .polished,
                                   rules: Language.english.rules) != .accept)
    }

    /// Ordinals that are everyday words ("andra" = others, "secondo" = according to) don't allow digits.
    @Test func everydayOrdinalsDontAllowDigits() {
        // Light must keep every word: "andra" turned into a digit is a dropped word, not a number.
        #expect(CleanupGuard.check(original: "de andra kommer sent idag", cleaned: "De 2 kommer sent idag.",
                                   level: .light, rules: Language.swedish.rules) != .accept)
        let everyday: [(Language, String)] = [(.swedish, "andra"), (.danish, "anden"), (.italian, "secondo"),
                                              (.portuguese, "segundo"), (.portuguese, "segunda")]
        let stillNumbers = everyday.filter { $0.0.rules.numberWords.contains($0.1) }.map(\.1)
        #expect(stillNumbers.isEmpty)
    }

    static let grammarFixes: [(String, String)] = [
        ("He go to the store yesterday and buyed some milk.", "He went to the store yesterday and bought some milk."),
        ("I has a apple. Their going to the park.", "I have an apple. They're going to the park."),
        ("She don't like it, its to late.", "She doesn't like it, it's too late."),
        ("Jag har en stort hus och hon gillar honom bil.", "Jag har ett stort hus och hon gillar hans bil."),
        ("Vi ska köpa en äpple imorgon.", "Vi ska köpa ett äpple imorgon."),
        ("Han har inte ätit något mat idag.", "Han har inte ätit någon mat idag."),
        ("Ich habe ein großer Hund und er sind sehr nett.", "Ich habe einen großen Hund und er ist sehr nett."),
        ("she do it", "She does it."),   // short verbs: "do"/"does", "go"/"goes"
        ("it go well", "It goes well."),
    ]

    @Test(arguments: grammarFixes)
    func grammarFixesPassLightWithGrammarOn(original: String, fixed: String) {
        let on = CleanupGuard.check(original: original, cleaned: fixed, level: .light, grammar: true)
        #expect(on == .accept)
        let off = CleanupGuard.check(original: original, cleaned: fixed, level: .light, grammar: false)
        #expect(off != .accept)
    }

    /// Grammar mode doesn't let an answer or added content through.
    @Test func grammarModeStillRejectsAddedContent() {
        let added = CleanupGuard.check(original: "send the report today",
                                       cleaned: "Send the report today and also book a flight to Paris for me.",
                                       level: .light, grammar: true)
        #expect(added != .accept)
        let answered = CleanupGuard.check(original: "what time is it in tokyo right now",
                                          cleaned: "It is 3 pm in Tokyo.", level: .polished, grammar: true)
        #expect(answered != .accept)
    }

    @Test func nearWords() {
        #expect(CleanupGuard.isNear("have", "has"))
        #expect(!CleanupGuard.isNear("bought", "buyed"))   // 4 edits: counted as new, within the 20 % limit
        #expect(CleanupGuard.isNear("an", "a"))
        #expect(CleanupGuard.isNear("doesn", "don"))
        #expect(!CleanupGuard.isNear("went", "go"))
        #expect(!CleanupGuard.isNear("hans", "honom"))
        // Cleanup pass: two-letter words are only near with one letter changed ("on" isn't "me").
        #expect(!CleanupGuard.isNear("on", "me"))
        #expect(!CleanupGuard.isNear("re", "to"))
        #expect(CleanupGuard.isNear("to", "too"))
    }

    // MARK: Swedish IT terms

    /// The model's repairs of real KB-Whisper mishearings from a read-aloud stand-up.
    @Test(arguments: [
        ("Jag mergade puller-orchestern igår kväll", "Jag mergade pull requesten igår kväll."),
        ("En av poddarna i kubenetesklustret kraschade", "En av poddarna i Kubernetes-klustret kraschade."),
        ("Vi flyttar loggarna från Elastic Search", "Vi flyttar loggarna från Elasticsearch."),
        ("Jag har skapat en ticket i Gira och lagt den i backloggen", "Jag har skapat en ticket i Jira och lagt den i backloggen."),
        ("De gamla endpoints är markerade som deprockated", "De gamla endpoints är markerade som deprecated."),
        ("Rotorsaken var en bugg i sessioner i Readis", "Rotorsaken var en bugg i sessioner i Redis."),
    ])
    func lightAcceptsATermRepair(heard: String, repaired: String) {
        #expect(CleanupGuard.check(original: heard, cleaned: repaired, level: .light, terms: true) == .accept)
    }

    @Test func termRepairsOnlyWhenAsked() {
        #expect(CleanupGuard.check(original: "Jag mergade puller-orchestern igår kväll",
                                   cleaned: "Jag mergade pull requesten igår kväll.", level: .light) != .accept)
    }

    /// A real word is what was said: "ploga åkern" never becomes "deploya åkern".
    @Test func aKnownWordIsNeverRepairedIntoATerm() {
        let verdict = CleanupGuard.check(original: "Vi ska ploga åkern i morgon", cleaned: "Vi ska deploya åkern i morgon.",
                                         level: .light, terms: true, isKnownWord: { $0 == "ploga" })
        #expect(verdict != .accept)
    }

    /// Real words the recogniser heard ("puller", "Gira") may still be terms when very close.
    @Test func aKnownWordVeryCloseToATermIsRepaired() {
        let known: (String) -> Bool = { ["puller", "gira", "quad"].contains($0) }
        #expect(CleanupGuard.check(original: "Jag mergade puller-orchestern igår kväll", cleaned: "Jag mergade pull requesten igår kväll.",
                                   level: .light, terms: true, isKnownWord: known) == .accept)
        #expect(CleanupGuard.check(original: "Jag har skapat en ticket i Gira", cleaned: "Jag har skapat en ticket i Jira.",
                                   level: .light, terms: true, isKnownWord: known) == .accept)
        // Two letters off a real word: left to the personal dictionary.
        #expect(CleanupGuard.check(original: "Fixen ligger för Quad Review", cleaned: "Fixen ligger för code review.",
                                   level: .light, terms: true, isKnownWord: known) != .accept)
    }

    /// Apple's model added this sentence to a line that ended "Vi skickar också".
    @Test func termsDoNotExcuseAnInventedSentence() {
        let verdict = CleanupGuard.check(original: "Det sparar ungefär 30 % av fakturan. Vi skickar också",
                                         cleaned: "Det sparar ungefär 30 % av fakturan. Vi skickar också en pull request till Kubernetes-klustret.",
                                         level: .light, terms: true)
        #expect(verdict != .accept)
    }
}
