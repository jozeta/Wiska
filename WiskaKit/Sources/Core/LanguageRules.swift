/// Everything cleanup needs to know about one language's words. All entries are lower-case.
public struct LanguageRules: Sendable, Equatable {
    /// Never real words: always removed.
    public var fillerSounds: Set<String>
    /// Words Polished may drop as fillers ("like", "typ"); Light must keep them.
    public var softFillers: Set<String>
    /// Fillers only as a phrase ("you know"); each word alone is a real word.
    public var fillerPhrases: [[String]]
    /// A dictation starting with one of these must stay a question.
    public var questionWords: Set<String>
    /// Spoken numbers may legitimately become digits.
    public var numberWords: Set<String>
    public var newLine: [String]
    public var newParagraph: [String]
    public var scratchThat: [String]
    /// A determiner before a command phrase means prose ("a new line of products").
    public var determiners: Set<String>
    /// An infinitive marker before "scratch that" means prose ("to scratch that itch").
    public var infinitiveMarkers: Set<String>
    /// Doubled words that are correct ("I had had enough", "die Frau, die die Zeitung liest").
    public var legitimateRepeats: Set<String>

    public init(fillerSounds: Set<String>, softFillers: Set<String>, fillerPhrases: [[String]],
                questionWords: Set<String>, numberWords: Set<String>,
                newLine: [String], newParagraph: [String], scratchThat: [String],
                determiners: Set<String>, infinitiveMarkers: Set<String>, legitimateRepeats: Set<String>) {
        self.fillerSounds = fillerSounds
        self.softFillers = softFillers
        self.fillerPhrases = fillerPhrases
        self.questionWords = questionWords
        self.numberWords = numberWords
        self.newLine = newLine
        self.newParagraph = newParagraph
        self.scratchThat = scratchThat
        self.determiners = determiners
        self.infinitiveMarkers = infinitiveMarkers
        self.legitimateRepeats = legitimateRepeats
    }

    static let empty = LanguageRules(fillerSounds: [], softFillers: [], fillerPhrases: [], questionWords: [],
                                     numberWords: [], newLine: [], newParagraph: [], scratchThat: [],
                                     determiners: [], infinitiveMarkers: [], legitimateRepeats: [])

    /// Every listed language's words at once — for text whose language is unknown.
    public static func merged(_ languages: [Language]) -> LanguageRules {
        var all = empty
        for rules in languages.map(\.rules) {
            all.fillerSounds.formUnion(rules.fillerSounds)
            all.softFillers.formUnion(rules.softFillers)
            all.fillerPhrases += rules.fillerPhrases
            all.questionWords.formUnion(rules.questionWords)
            all.numberWords.formUnion(rules.numberWords)
            all.newLine += rules.newLine
            all.newParagraph += rules.newParagraph
            all.scratchThat += rules.scratchThat
            all.determiners.formUnion(rules.determiners)
            all.infinitiveMarkers.formUnion(rules.infinitiveMarkers)
            all.legitimateRepeats.formUnion(rules.legitimateRepeats)
        }
        // A filler sound in one language can be a real word in another (English "um" is
        // Portuguese "a"): when the language is unknown, keep the word.
        all.fillerSounds.subtract(all.questionWords.union(all.numberWords).union(all.determiners))
        return all
    }

    /// English + Swedish: what cleanup used before languages were configurable.
    public static let `default` = merged([.english, .swedish])
}

extension Language {
    public var rules: LanguageRules {
        switch self {
        case .english:
            LanguageRules(
                fillerSounds: ["um", "umm", "uh", "uhm", "erm", "ehm", "hmm"],
                softFillers: ["like", "basically", "actually", "well"],
                fillerPhrases: [["you", "know"]],
                questionWords: ["what", "who", "when", "where", "why", "how", "which", "is", "are", "can",
                                "could", "do", "does"],
                numberWords: ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
                              "ten", "eleven", "twelve", "fifteen", "twenty", "thirty", "forty", "fifty",
                              "hundred", "thousand", "half", "quarter"],
                newLine: ["new line"], newParagraph: ["new paragraph"], scratchThat: ["scratch that"],
                determiners: ["a", "an", "the", "this", "that", "these", "my", "our", "your", "their", "his",
                              "her", "its"],
                infinitiveMarkers: ["to"],
                legitimateRepeats: ["had", "that"])
        case .swedish:
            LanguageRules(
                fillerSounds: ["öh", "eh", "äh", "ehh"],
                softFillers: ["typ", "liksom", "alltså", "asså"],
                fillerPhrases: [],
                questionWords: ["vad", "vem", "när", "var", "varför", "hur", "vilken", "vilket", "vilka", "kan",
                                "är"],
                numberWords: ["noll", "ett", "två", "tre", "fyra", "fem", "sex", "sju", "åtta", "nio", "tio",
                              "elva", "tolv", "femton", "tjugo", "trettio", "fyrtio", "femtio", "hundra",
                              "tusen", "halv", "kvart"],
                newLine: ["ny rad"], newParagraph: ["nytt stycke"], scratchThat: ["stryk det"],
                determiners: ["en", "ett", "den", "det", "denna", "detta", "min", "mitt", "din", "ditt", "vår",
                              "vårt", "er", "ert", "hans", "hennes", "deras", "sin", "sitt"],
                infinitiveMarkers: ["att"],
                legitimateRepeats: [])
        case .german:
            LanguageRules(
                fillerSounds: ["äh", "ähm", "öhm", "hm", "hmm", "ehm"],
                softFillers: ["also", "halt", "quasi", "sozusagen"],
                fillerPhrases: [],
                questionWords: ["was", "wer", "wann", "wo", "warum", "wie", "welche", "welcher", "welches",
                                "kann", "können", "ist", "sind", "hast", "hat"],
                numberWords: ["null", "eins", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun",
                              "zehn", "elf", "zwölf", "fünfzehn", "zwanzig", "dreißig", "vierzig", "fünfzig",
                              "hundert", "tausend", "halb", "viertel"],
                newLine: ["neue zeile"], newParagraph: ["neuer absatz"], scratchThat: ["streich das"],
                determiners: ["ein", "eine", "einen", "einem", "einer", "der", "die", "das", "den", "dem", "des",
                              "dieser", "diese", "dieses", "mein", "meine", "dein", "deine", "unser", "unsere",
                              "ihr", "ihre", "sein", "seine"],
                infinitiveMarkers: ["zu"],
                legitimateRepeats: ["der", "die", "das"])
        case .french:
            LanguageRules(
                fillerSounds: ["euh", "heu", "hum", "hm"],
                softFillers: ["genre", "bah", "ben", "bref", "quoi"],
                fillerPhrases: [],
                questionWords: ["qui", "quoi", "quand", "où", "pourquoi", "comment", "quel", "quelle", "quels",
                                "quelles", "est"],
                numberWords: ["zéro", "un", "une", "deux", "trois", "quatre", "cinq", "six", "sept", "huit",
                              "neuf", "dix", "onze", "douze", "quinze", "vingt", "trente", "quarante",
                              "cinquante", "cent", "mille", "demi", "quart"],
                newLine: ["nouvelle ligne"], newParagraph: ["nouveau paragraphe"], scratchThat: ["efface ça"],
                determiners: ["un", "une", "le", "la", "les", "ce", "cette", "ces", "mon", "ma", "mes", "ton",
                              "ta", "tes", "son", "sa", "ses", "notre", "votre", "leur"],
                infinitiveMarkers: ["de"],
                legitimateRepeats: ["nous", "vous"])
        case .spanish:
            LanguageRules(
                fillerSounds: ["eh", "ehm", "mmm", "hmm"],
                softFillers: ["pues", "bueno", "tipo"],
                fillerPhrases: [["o", "sea"]],
                questionWords: ["qué", "quién", "quiénes", "cuándo", "dónde", "cómo", "cuál", "cuáles", "puedes",
                                "puede", "es"],
                numberWords: ["cero", "uno", "una", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho",
                              "nueve", "diez", "once", "doce", "quince", "veinte", "treinta", "cuarenta",
                              "cincuenta", "cien", "mil", "media", "cuarto"],
                newLine: ["nueva línea"], newParagraph: ["nuevo párrafo"], scratchThat: ["borra eso"],
                determiners: ["un", "una", "el", "la", "los", "las", "este", "esta", "estos", "estas", "mi",
                              "mis", "tu", "tus", "su", "sus", "nuestro", "nuestra"],
                infinitiveMarkers: [],
                legitimateRepeats: [])
        case .italian:
            LanguageRules(
                fillerSounds: ["ehm", "eh", "mmm", "uhm"],
                softFillers: ["cioè", "tipo", "insomma", "praticamente"],
                fillerPhrases: [],
                questionWords: ["che", "chi", "cosa", "quando", "dove", "perché", "come", "quale", "quali",
                                "puoi", "è"],
                numberWords: ["zero", "uno", "una", "due", "tre", "quattro", "cinque", "sei", "sette", "otto",
                              "nove", "dieci", "undici", "dodici", "quindici", "venti", "trenta", "quaranta",
                              "cinquanta", "cento", "mille", "mezza", "quarto"],
                newLine: ["nuova riga"], newParagraph: ["nuovo paragrafo"], scratchThat: ["cancella quello"],
                determiners: ["un", "una", "uno", "il", "lo", "la", "i", "gli", "le", "questo", "questa", "mio",
                              "mia", "tuo", "tua", "suo", "sua", "nostro", "nostra"],
                infinitiveMarkers: ["di"],
                legitimateRepeats: [])
        case .portuguese:
            LanguageRules(
                fillerSounds: ["hum", "hã", "ahn", "mmm"],
                softFillers: ["tipo", "pronto", "portanto"],
                fillerPhrases: [["quer", "dizer"]],
                questionWords: ["que", "quem", "quando", "onde", "porque", "porquê", "como", "qual", "quais",
                                "pode", "é"],
                numberWords: ["zero", "um", "uma", "dois", "duas", "três", "quatro", "cinco", "seis", "sete",
                              "oito", "nove", "dez", "onze", "doze", "quinze", "vinte", "trinta", "quarenta",
                              "cinquenta", "cem", "mil", "meia", "quarto"],
                newLine: ["nova linha"], newParagraph: ["novo parágrafo"], scratchThat: ["apaga isso"],
                determiners: ["um", "uma", "o", "a", "os", "as", "este", "esta", "meu", "minha", "teu", "tua",
                              "seu", "sua", "nosso", "nossa"],
                infinitiveMarkers: ["de"],
                legitimateRepeats: [])
        case .danish:
            LanguageRules(
                fillerSounds: ["øh", "øhm", "æh", "hm"],
                softFillers: ["altså", "ligesom"],
                fillerPhrases: [],
                questionWords: ["hvad", "hvem", "hvornår", "hvor", "hvorfor", "hvordan", "hvilken", "hvilket",
                                "hvilke", "kan", "er"],
                numberWords: ["nul", "en", "et", "to", "tre", "fire", "fem", "seks", "syv", "otte", "ni", "ti",
                              "elleve", "tolv", "femten", "tyve", "tredive", "fyrre", "halvtreds", "hundrede",
                              "tusind", "halv", "kvart"],
                newLine: ["ny linje"], newParagraph: ["nyt afsnit"], scratchThat: ["slet det"],
                determiners: ["en", "et", "den", "det", "denne", "dette", "min", "mit", "din", "dit", "vores",
                              "jeres", "hans", "hendes", "deres", "sin", "sit"],
                infinitiveMarkers: ["at"],
                legitimateRepeats: [])
        case .dutch:
            LanguageRules(
                fillerSounds: ["uh", "uhm", "ehm", "eh", "hmm"],
                softFillers: ["dus", "eigenlijk"],
                fillerPhrases: [["zeg", "maar"]],
                questionWords: ["wat", "wie", "wanneer", "waar", "waarom", "hoe", "welke", "welk", "kan", "is",
                                "zijn"],
                numberWords: ["nul", "een", "één", "twee", "drie", "vier", "vijf", "zes", "zeven", "acht",
                              "negen", "tien", "elf", "twaalf", "vijftien", "twintig", "dertig", "veertig",
                              "vijftig", "honderd", "duizend", "half", "kwart"],
                newLine: ["nieuwe regel"], newParagraph: ["nieuwe alinea"], scratchThat: ["schrap dat"],
                determiners: ["een", "de", "het", "deze", "dit", "die", "dat", "mijn", "jouw", "je", "zijn",
                              "haar", "ons", "onze", "hun"],
                infinitiveMarkers: ["te"],
                legitimateRepeats: [])
        }
    }
}
