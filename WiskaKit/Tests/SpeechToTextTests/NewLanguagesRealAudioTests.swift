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

    /// Auto-detect among ticked languages, at most five at a time (Apple's limit). English and
    /// Svenska stay ticked in every group; each new language is spoken once.
    @Test(.timeLimit(.minutes(15)))
    func appleAutoDetectPicksTheSpokenLanguage() async throws {
        let groups: [[Language]] = [[.german, .french, .spanish], [.italian, .portuguese, .danish], [.dutch]]
        var misses: [String] = []
        for group in groups {
            let ticked: [Language] = [.english, .swedish] + group
            let transcriber = AppleTranscriber(languages: { ticked }, fallbackLanguage: { .english })
            for sample in Self.samples where group.contains(sample.language) {
                let audio = try SpeechSamples.spoken(sample.sentence, voice: sample.voice)
                let session = try await transcriber.makeSession(language: .automatic)
                let detected = try await SpeechSamples.transcribe(audio, with: session).language
                if detected != sample.language { misses.append("\(sample.language) → \(String(describing: detected))") }
            }
            await AppleTranscriber.release(group)
        }
        print("auto-detect misses: \(misses)")
        #expect(misses.count <= 1, "\(misses)")
    }
}
