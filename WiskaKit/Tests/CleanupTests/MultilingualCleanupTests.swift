import Core
import Testing
@testable import Cleanup

struct MultilingualCleanupTests {
    @Test(arguments: [
        (Language.german, "äh ich glaube ähm das passt", "Ich glaube das passt."),
        (.french, "euh je pense que heu ça marche", "Je pense que ça marche."),
        (.spanish, "eh creo que mmm funciona", "Creo que funciona."),
        (.italian, "ehm penso che uhm funzioni", "Penso che funzioni."),
        (.portuguese, "hum acho que hã funciona", "Acho que funciona."),
        (.danish, "øh jeg tror æh det virker", "Jeg tror det virker."),
        (.dutch, "uh ik denk uhm dat het werkt", "Ik denk dat het werkt."),
    ])
    func fillerSoundsAreRemovedPerLanguage(language: Language, input: String, expected: String) {
        #expect(RuleCleaner.clean(input, rules: language.rules) == expected)
    }

    @Test(arguments: [
        (Language.german, "erste Zeile neue Zeile zweite Zeile", "erste Zeile\nzweite Zeile"),
        (.french, "bonjour nouvelle ligne merci", "bonjour\nmerci"),
        (.spanish, "hola nueva línea gracias", "hola\ngracias"),
        (.italian, "ciao nuova riga grazie", "ciao\ngrazie"),
        (.portuguese, "olá nova linha obrigado", "olá\nobrigado"),
        (.danish, "hej ny linje tak", "hej\ntak"),
        (.dutch, "hallo nieuwe regel bedankt", "hallo\nbedankt"),
    ])
    func newLineCommandPerLanguage(language: Language, input: String, expected: String) {
        #expect(VoiceCommands.apply(input, rules: language.rules) == expected)
    }

    @Test func scratchThatPerLanguage() {
        #expect(VoiceCommands.apply("falsch streich das richtig", rules: Language.german.rules) == "richtig")
        #expect(VoiceCommands.apply("faux efface ça vrai", rules: Language.french.rules) == "vrai")
    }

    @Test func determinerKeepsProse() {
        #expect(VoiceCommands.apply("eine neue Zeile im Text", rules: Language.german.rules) == "eine neue Zeile im Text")
    }

    @Test func spanishFillersNeverTouchPortuguese() {
        let text = "este carro está em casa"
        #expect(RuleCleaner.clean(text, rules: Language.portuguese.rules) == "Este carro está em casa.")
        #expect(RuleCleaner.clean(text, rules: LanguageRules.merged([.spanish, .portuguese]))
                == "Este carro está em casa.")
    }

    @Test func germanRelativeRepeatIsKept() {
        #expect(RuleCleaner.clean("die Frau die die Zeitung liest", rules: Language.german.rules)
                == "Die Frau die die Zeitung liest.")
    }

    @Test func questionStaysAQuestionInFrench() {
        #expect(CleanupGuard.check(original: "pourquoi tu pars si tôt", cleaned: "Tu pars si tôt.",
                                   level: .polished, rules: Language.french.rules) != .accept)
    }
}
