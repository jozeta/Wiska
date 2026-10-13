/// A punctuation mark said aloud: "question mark" → "?".
public struct SpokenMark: Sendable, Equatable {
    public let phrases: [String]
    public let mark: String
    /// Words that are often ordinary prose ("trial period", "à ce point") count as the mark
    /// only as the dictation's last words.
    public let onlyAtEnd: Bool
    /// Also an ordinary noun ("the colon", "en punkt"): after a determiner it stays a word.
    public let isNoun: Bool

    public init(_ phrases: [String], _ mark: String, onlyAtEnd: Bool = false, isNoun: Bool = false) {
        self.phrases = phrases
        self.mark = mark
        self.onlyAtEnd = onlyAtEnd
        self.isNoun = isNoun
    }
}

extension Language {
    /// Punctuation said aloud. Words that are mostly something else ("komma", Swedish for "come")
    /// are left out.
    var spokenMarks: [SpokenMark] {
        switch self {
        case .english: [
            SpokenMark(["comma"], ","), SpokenMark(["full stop"], "."), SpokenMark(["period"], ".", onlyAtEnd: true, isNoun: true),
            SpokenMark(["question mark"], "?"), SpokenMark(["exclamation mark", "exclamation point"], "!"),
            SpokenMark(["colon"], ":", isNoun: true), SpokenMark(["semicolon", "semi colon"], ";")]
        case .swedish: [
            SpokenMark(["kommatecken"], ","), SpokenMark(["punkt"], ".", isNoun: true), SpokenMark(["frågetecken"], "?"),
            SpokenMark(["utropstecken"], "!"), SpokenMark(["kolon"], ":"), SpokenMark(["semikolon"], ";")]
        case .german: [
            SpokenMark(["komma"], ","), SpokenMark(["punkt"], ".", onlyAtEnd: true, isNoun: true), SpokenMark(["fragezeichen"], "?"),
            SpokenMark(["ausrufezeichen"], "!"), SpokenMark(["doppelpunkt"], ":"), SpokenMark(["semikolon"], ";")]
        case .french: [
            SpokenMark(["virgule"], ","), SpokenMark(["point final"], "."), SpokenMark(["point"], ".", onlyAtEnd: true, isNoun: true),
            SpokenMark(["point d'interrogation"], "?"), SpokenMark(["point d'exclamation"], "!"),
            SpokenMark(["deux-points", "deux points"], ":"), SpokenMark(["point-virgule", "point virgule"], ";")]
        case .spanish: [
            SpokenMark(["coma"], ","), SpokenMark(["punto final", "punto y seguido"], "."),
            SpokenMark(["signo de interrogación"], "?"), SpokenMark(["signo de exclamación"], "!"),
            SpokenMark(["dos puntos"], ":"), SpokenMark(["punto y coma"], ";")]
        case .italian: [
            SpokenMark(["virgola"], ","), SpokenMark(["punto fermo"], "."), SpokenMark(["punto interrogativo"], "?"),
            SpokenMark(["punto esclamativo"], "!"), SpokenMark(["due punti"], ":"), SpokenMark(["punto e virgola"], ";")]
        case .portuguese: [
            SpokenMark(["vírgula"], ","), SpokenMark(["ponto final"], "."), SpokenMark(["ponto de interrogação"], "?"),
            SpokenMark(["ponto de exclamação"], "!"), SpokenMark(["dois pontos"], ":"), SpokenMark(["ponto e vírgula"], ";")]
        case .danish: [
            SpokenMark(["komma"], ","), SpokenMark(["punktum"], "."), SpokenMark(["spørgsmålstegn"], "?"),
            SpokenMark(["udråbstegn"], "!"), SpokenMark(["kolon"], ":"), SpokenMark(["semikolon"], ";")]
        case .dutch: [
            SpokenMark(["komma"], ","), SpokenMark(["punt"], ".", onlyAtEnd: true, isNoun: true), SpokenMark(["vraagteken"], "?"),
            SpokenMark(["uitroepteken"], "!"), SpokenMark(["dubbele punt"], ":"), SpokenMark(["puntkomma"], ";")]
        }
    }

    /// Removes the sentence said just before it.
    var deleteSentencePhrases: [String] {
        switch self {
        case .english: ["delete last sentence", "undo that"]
        case .swedish: ["radera sista meningen", "ångra det"]
        case .german: ["letzten satz löschen", "mach das rückgängig"]
        case .french: ["supprime la dernière phrase", "annule ça"]
        case .spanish: ["borra la última frase", "deshaz eso"]
        case .italian: ["cancella l'ultima frase", "annulla quello"]
        case .portuguese: ["apaga a última frase", "desfaz isso"]
        case .danish: ["slet sidste sætning", "fortryd det"]
        case .dutch: ["verwijder laatste zin", "maak dat ongedaan"]
        }
    }
}
