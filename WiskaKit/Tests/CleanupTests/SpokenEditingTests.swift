import Core
import Testing
@testable import Cleanup

/// "delete last sentence", "undo that" and punctuation said aloud, in every language.
struct SpokenEditingTests {
    @Test(arguments: [
        ("I like cats. I hate dogs. Delete last sentence. I love birds.", "I like cats. I love birds."),
        ("I like cats. I hate dogs, undo that", "I like cats."),
        ("delete last sentence", ""),
        ("One. Two. Delete last sentence. Delete last sentence. Three.", "Three."),
        ("I want to undo that change", "I want to undo that change"),   // prose after "to"
    ])
    func englishSentenceDeletion(input: String, expected: String) {
        #expect(VoiceCommands.apply(input, rules: Language.english.rules) == expected)
    }

    @Test(arguments: [
        ("Hello comma how are you question mark", "Hello, how are you?"),
        ("Hello, comma, how are you?", "Hello, how are you?"),
        ("Wait exclamation mark it works full stop", "Wait! It works."),
        ("Three things colon apples semicolon pears", "Three things: apples; pears"),
        ("See you tomorrow period", "See you tomorrow."),
        ("The trial period ends today", "The trial period ends today"),    // "period" only at the end
        ("Please describe the colon", "Please describe the colon"),          // a determiner: prose
    ])
    func englishPunctuation(input: String, expected: String) {
        #expect(VoiceCommands.apply(input, rules: Language.english.rules) == expected)
    }

    @Test(arguments: [
        (Language.swedish, "Hej kommatecken hur mår du frågetecken", "Hej, hur mår du?"),
        (.swedish, "Jag ska komma imorgon", "Jag ska komma imorgon"),   // "komma" is a verb: not a mark
        (.swedish, "Ett. Två. Radera sista meningen. Tre.", "Ett. Tre."),
        (.german, "Hallo Komma wie geht es dir Fragezeichen", "Hallo, wie geht es dir?"),
        (.german, "Es kostet 3 Komma 5 Euro", "Es kostet 3 Komma 5 Euro"),     // a decimal comma
        (.french, "Bonjour virgule ça va point d'interrogation", "Bonjour, ça va?"),
        (.french, "Une liste deux-points pommes point-virgule poires", "Une liste: pommes; poires"),
        (.french, "À ce point je pars", "À ce point je pars"),           // "point" only at the end
        (.spanish, "Hola coma qué tal punto final", "Hola, qué tal."),
        (.italian, "Ciao virgola come stai punto interrogativo", "Ciao, come stai?"),
        (.portuguese, "Olá vírgula tudo bem ponto de interrogação", "Olá, tudo bem?"),
        (.danish, "Hej komma hvordan går det spørgsmålstegn", "Hej, hvordan går det?"),
        (.dutch, "Hallo komma hoe gaat het vraagteken", "Hallo, hoe gaat het?"),
        (.dutch, "Op dit punt stoppen we", "Op dit punt stoppen we"),
    ])
    func everyLanguage(language: Language, input: String, expected: String) {
        #expect(VoiceCommands.apply(input, rules: language.rules) == expected)
    }

    @Test func everyLanguageHasMarksAndSentenceDeletion() {
        for language in Language.allCases {
            #expect(language.rules.spokenMarks.count >= 6, "\(language)")
            #expect(!language.rules.deleteSentence.isEmpty, "\(language)")
        }
    }

    @Test func mergedRulesKeepEveryLanguagesCommands() {
        let merged = LanguageRules.merged([.english, .swedish])
        #expect(VoiceCommands.apply("Hej kommatecken hello question mark", rules: merged) == "Hej, hello?")
    }
}
