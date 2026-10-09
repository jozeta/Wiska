/// The words formatting needs in one language. All entries are lower-case; phrases are word arrays.
public struct FormatRules: Sendable, Equatable {
    /// `listMarkers[n]`: spoken forms that start list item n+1 (each may be several words).
    public var listMarkers: [[String]]
    /// "and", "then": a list marker may follow one of these instead of a comma.
    public var conjunctions: Set<String>
    /// Words that open an email greeting ("hi", "sehr geehrte").
    public var greetings: [[String]]
    /// Phrases that close an email ("best regards", "mvh").
    public var signOffs: [[String]]
    /// Ordinals and the percent word: spoken numbers that may legitimately become digits. Ordinals
    /// that are also everyday words (Swedish "andra" = others, Italian "secondo" = according to)
    /// are left out, so they never excuse digits.
    public var numberExtras: Set<String>
    /// Words that, right after a one-word marker, show it is an ordinary word ("second place",
    /// Italian "secondo me" = "in my opinion", Portuguese "segundo o João" = "according to João").
    public var markerBlockers: Set<String>
    /// "insert", "infoga": the word that asks for a snippet.
    public var insertWords: [[String]]
    /// "my", "min/mitt/mina": optional between the insert word and the snippet's name.
    public var possessives: [[String]]

    public init(listMarkers: [[String]], conjunctions: Set<String>, greetings: [[String]],
                signOffs: [[String]], numberExtras: Set<String>, markerBlockers: Set<String> = [],
                insertWords: [[String]] = [], possessives: [[String]] = []) {
        self.listMarkers = listMarkers
        self.conjunctions = conjunctions
        self.greetings = greetings
        self.signOffs = signOffs
        self.numberExtras = numberExtras
        self.markerBlockers = markerBlockers
        self.insertWords = insertWords
        self.possessives = possessives
    }

    /// Every listed language's words at once — for text whose language is unknown.
    public static func merged(_ languages: [Language]) -> FormatRules {
        var all = FormatRules(listMarkers: Array(repeating: [], count: 10), conjunctions: [], greetings: [],
                              signOffs: [], numberExtras: [])
        for rules in languages.map(\.formatRules) {
            for (index, forms) in rules.listMarkers.enumerated() { all.listMarkers[index] += forms }
            all.conjunctions.formUnion(rules.conjunctions)
            all.greetings += rules.greetings
            all.signOffs += rules.signOffs
            all.numberExtras.formUnion(rules.numberExtras)
            all.markerBlockers.formUnion(rules.markerBlockers)
            all.insertWords += rules.insertWords
            all.possessives += rules.possessives
        }
        return all
    }
}

private func phrases(_ list: [String]) -> [[String]] {
    list.map { $0.split(separator: " ").map(String.init) }
}

extension Language {
    public var formatRules: FormatRules {
        switch self {
        case .english:
            FormatRules(
                listMarkers: [["first", "firstly", "number one"], ["second", "secondly", "number two"],
                              ["third", "thirdly", "number three"], ["fourth", "fourthly", "number four"],
                              ["fifth", "fifthly", "number five"], ["sixth", "number six"],
                              ["seventh", "number seven"], ["eighth", "number eight"], ["ninth", "number nine"],
                              ["tenth", "number ten"]],
                conjunctions: ["and", "then"],
                greetings: phrases(["hi", "hello", "hey", "dear"]),
                signOffs: phrases(["best", "best regards", "kind regards", "regards", "thanks", "thank you",
                                   "cheers", "all the best", "sincerely"]),
                numberExtras: ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth",
                               "ninth", "tenth", "eleventh", "twelfth", "percent"],
                markerBlockers: ["place", "prize", "time", "hand", "half", "class", "floor", "round", "thought",
                                 "person", "row", "of", "best", "language", "opinion", "chance"],
                insertWords: phrases(["insert"]), possessives: phrases(["my"]))
        case .swedish:
            FormatRules(
                listMarkers: [["först", "för det första", "nummer ett"], ["för det andra", "nummer två"],
                              ["för det tredje", "tredje", "nummer tre"], ["för det fjärde", "fjärde", "nummer fyra"],
                              ["för det femte", "femte", "nummer fem"], ["för det sjätte", "sjätte", "nummer sex"],
                              ["sjunde", "nummer sju"], ["åttonde", "nummer åtta"], ["nionde", "nummer nio"],
                              ["tionde", "nummer tio"]],
                conjunctions: ["och", "sen", "sedan"],
                greetings: phrases(["hej", "hejsan", "hallå", "kära", "tjena"]),
                signOffs: phrases(["med vänliga hälsningar", "vänliga hälsningar", "hälsningar", "mvh", "tack",
                                   "hej då", "ha det bra"]),
                numberExtras: ["första", "tredje", "fjärde", "femte", "sjätte", "sjunde", "åttonde",
                               "nionde", "tionde", "elfte", "tolfte", "procent"],
                insertWords: phrases(["infoga", "lägg in"]), possessives: phrases(["min", "mitt", "mina"]))
        case .german:
            FormatRules(
                listMarkers: [["erstens", "zuerst", "nummer eins"], ["zweitens", "nummer zwei"],
                              ["drittens", "nummer drei"], ["viertens", "nummer vier"], ["fünftens", "nummer fünf"],
                              ["sechstens", "nummer sechs"], ["siebtens", "nummer sieben"], ["achtens", "nummer acht"],
                              ["neuntens", "nummer neun"], ["zehntens", "nummer zehn"]],
                conjunctions: ["und", "dann"],
                greetings: phrases(["hallo", "hi", "liebe", "lieber", "sehr geehrte", "sehr geehrter", "guten tag",
                                    "moin"]),
                signOffs: phrases(["mit freundlichen grüßen", "viele grüße", "liebe grüße", "beste grüße", "grüße",
                                   "gruß", "danke"]),
                numberExtras: ["erste", "ersten", "zweite", "zweiten", "dritte", "dritten", "vierte", "vierten",
                               "fünfte", "fünften", "sechste", "sechsten", "siebte", "siebten", "achte", "achten",
                               "neunte", "neunten", "zehnte", "zehnten", "elfte", "elften", "zwölfte", "zwölften",
                               "prozent"],
                insertWords: phrases(["einfügen", "füge ein"]), possessives: phrases(["mein", "meine", "meinen"]))
        case .french:
            FormatRules(
                listMarkers: [["premièrement", "premier", "première", "numéro un"],
                              ["deuxièmement", "deuxième", "second", "seconde", "numéro deux"],
                              ["troisièmement", "troisième", "numéro trois"], ["quatrièmement", "quatrième", "numéro quatre"],
                              ["cinquièmement", "cinquième", "numéro cinq"], ["sixièmement", "sixième", "numéro six"],
                              ["septièmement", "septième", "numéro sept"], ["huitièmement", "huitième", "numéro huit"],
                              ["neuvièmement", "neuvième", "numéro neuf"], ["dixièmement", "dixième", "numéro dix"]],
                conjunctions: ["et", "puis"],
                greetings: phrases(["bonjour", "salut", "cher", "chère", "coucou"]),
                signOffs: phrases(["cordialement", "bien à vous", "merci", "bonne journée", "amicalement"]),
                numberExtras: ["premier", "première", "deuxième", "troisième", "quatrième", "cinquième", "sixième",
                               "septième", "huitième", "neuvième", "dixième", "onzième", "douzième"],
                insertWords: phrases(["insérer", "insère"]), possessives: phrases(["mon", "ma", "mes"]))
        case .spanish:
            FormatRules(
                listMarkers: [["primero", "primera", "en primer lugar", "número uno"],
                              ["segundo", "segunda", "en segundo lugar", "número dos"],
                              ["tercero", "tercera", "en tercer lugar", "número tres"],
                              ["cuarto", "cuarta", "en cuarto lugar", "número cuatro"], ["quinto", "quinta", "número cinco"],
                              ["sexto", "sexta", "número seis"], ["séptimo", "séptima", "número siete"],
                              ["octavo", "octava", "número ocho"], ["noveno", "novena", "número nueve"],
                              ["décimo", "décima", "número diez"]],
                conjunctions: ["y", "luego"],
                greetings: phrases(["hola", "querido", "querida", "estimado", "estimada", "buenos días"]),
                signOffs: phrases(["un saludo", "saludos", "atentamente", "gracias", "un abrazo"]),
                numberExtras: ["primero", "primera", "segundo", "segunda", "tercero", "tercera", "cuarto", "quinto",
                               "sexto", "séptimo", "octavo", "noveno", "décimo", "ciento"],
                markerBlockers: ["lugar", "plato", "piso"],
                insertWords: phrases(["insertar", "inserta"]), possessives: phrases(["mi", "mis"]))
        case .italian:
            FormatRules(
                listMarkers: [["primo", "innanzitutto", "numero uno"], ["secondo", "numero due"],
                              ["terzo", "numero tre"], ["quarto", "numero quattro"], ["quinto", "numero cinque"],
                              ["sesto", "numero sei"], ["settimo", "numero sette"], ["ottavo", "numero otto"],
                              ["nono", "numero nove"], ["decimo", "numero dieci"]],
                conjunctions: ["e", "poi"],
                greetings: phrases(["ciao", "salve", "caro", "cara", "gentile", "buongiorno"]),
                signOffs: phrases(["cordiali saluti", "un saluto", "saluti", "grazie", "a presto"]),
                numberExtras: ["primo", "terzo", "quarto", "quinto", "sesto", "settimo", "ottavo", "nono",
                               "decimo"],
                markerBlockers: ["me", "te", "lui", "lei", "noi", "voi", "loro", "il", "la", "lo", "i", "gli", "le",
                                 "piatto", "posto", "tempo"],
                insertWords: phrases(["inserisci", "inserire"]), possessives: phrases(["il mio", "la mia", "mio", "mia"]))
        case .portuguese:
            FormatRules(
                listMarkers: [["primeiro", "primeira", "em primeiro lugar", "número um"],
                              ["segundo", "segunda", "em segundo lugar", "número dois"],
                              ["terceiro", "terceira", "número três"], ["quarto", "quarta", "número quatro"],
                              ["quinto", "quinta", "número cinco"], ["sexto", "sexta", "número seis"],
                              ["sétimo", "sétima", "número sete"], ["oitavo", "oitava", "número oito"],
                              ["nono", "nona", "número nove"], ["décimo", "décima", "número dez"]],
                conjunctions: ["e", "depois"],
                greetings: phrases(["olá", "oi", "caro", "cara", "prezado", "prezada", "bom dia"]),
                signOffs: phrases(["atenciosamente", "cumprimentos", "obrigado", "obrigada", "um abraço", "abraços"]),
                numberExtras: ["primeiro", "primeira", "terceiro", "quarto", "quinto", "sexto", "sétimo",
                               "oitavo", "nono", "décimo"],
                markerBlockers: ["o", "a", "os", "as", "ele", "ela", "eles", "elas", "lugar"],
                insertWords: phrases(["inserir", "insere"]), possessives: phrases(["o meu", "a minha", "meu", "minha"]))
        case .danish:
            FormatRules(
                listMarkers: [["først", "for det første", "nummer et"], ["for det andet", "nummer to"],
                              ["for det tredje", "tredje", "nummer tre"], ["for det fjerde", "fjerde", "nummer fire"],
                              ["for det femte", "femte", "nummer fem"], ["for det sjette", "sjette", "nummer seks"],
                              ["syvende", "nummer syv"], ["ottende", "nummer otte"], ["niende", "nummer ni"],
                              ["tiende", "nummer ti"]],
                conjunctions: ["og", "så"],
                greetings: phrases(["hej", "hejsa", "kære", "hallo"]),
                signOffs: phrases(["med venlig hilsen", "venlig hilsen", "de bedste hilsner", "hilsen", "mvh", "tak"]),
                numberExtras: ["første", "tredje", "fjerde", "femte", "sjette", "syvende", "ottende",
                               "niende", "tiende", "ellevte", "tolvte", "procent"],
                insertWords: phrases(["indsæt"]), possessives: phrases(["min", "mit", "mine"]))
        case .dutch:
            FormatRules(
                listMarkers: [["eerst", "ten eerste", "nummer een"], ["ten tweede", "nummer twee"],
                              ["ten derde", "derde", "nummer drie"], ["ten vierde", "vierde", "nummer vier"],
                              ["ten vijfde", "vijfde", "nummer vijf"], ["ten zesde", "zesde", "nummer zes"],
                              ["zevende", "nummer zeven"], ["achtste", "nummer acht"], ["negende", "nummer negen"],
                              ["tiende", "nummer tien"]],
                conjunctions: ["en", "dan"],
                greetings: phrases(["hoi", "hallo", "hey", "beste", "lieve", "geachte", "goedemorgen"]),
                signOffs: phrases(["met vriendelijke groet", "vriendelijke groet", "groetjes", "groeten", "bedankt",
                                   "dank je"]),
                numberExtras: ["eerste", "tweede", "derde", "vierde", "vijfde", "zesde", "zevende", "achtste",
                               "negende", "tiende", "elfde", "twaalfde", "procent"],
                insertWords: phrases(["invoegen", "voeg in"]), possessives: phrases(["mijn"]))
        }
    }
}
