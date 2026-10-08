import Core
import Foundation
import Testing
@testable import SpeechToText

/// One sentence per new language, spoken by that language's system voice.
/// Serialized, and each test releases what it reserved: Apple allows 5 reserved locales per app,
/// and the test runner is one app.
@MainActor @Suite(.serialized)
struct NewLanguagesRealAudioTests {
    static let samples: [(language: Language, voice: String, sentence: String, keyword: String)] = [
        (.german, "Anna", "Kannst du mir den Bericht vor dem Mittagessen schicken", "bericht"),
        (.french, "Thomas", "Peux-tu m'envoyer le rapport avant le déjeuner", "rapport"),
        (.spanish, "Paulina", "Puedes enviarme el informe antes del almuerzo", "informe"),
        (.italian, "Alice", "Puoi mandarmi il rapporto prima di pranzo", "rapporto"),
        (.portuguese, "Joana", "Podes enviar-me o relatório antes do almoço", "relatório"),
        (.danish, "Sara", "Kan du sende mig rapporten før frokost", "rapporten"),
        (.dutch, "Xander", "Kun je mij het rapport voor de lunch sturen", "rapport"),
    ]

    @Test(.timeLimit(.minutes(10)), arguments: 0..<7)
    func appleTranscribesEachNewLanguage(index: Int) async throws {
        let sample = Self.samples[index]
        let transcriber = AppleTranscriber(languages: { [sample.language] })
        let audio = try SpeechSamples.spoken(sample.sentence, voice: sample.voice)
        let session = try await transcriber.makeSession(language: .fixed(sample.language))
        let transcript = try await SpeechSamples.transcribe(audio, with: session)
        await AppleTranscriber.release([sample.language])
        #expect(transcript.language == sample.language)
        #expect(transcript.text.lowercased().contains(sample.keyword), "\(sample.language): \(transcript.text)")
    }
}
