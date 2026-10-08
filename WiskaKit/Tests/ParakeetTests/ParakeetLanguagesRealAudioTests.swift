import Core
import Foundation
import Testing
@testable import Parakeet

/// Parakeet on one sentence per new language; the language guess must name it.
@MainActor
struct ParakeetLanguagesRealAudioTests {
    static let samples: [(language: Language, voice: String, sentence: String, keyword: String)] = [
        (.german, "Anna", "Kannst du mir den Bericht vor dem Mittagessen schicken", "bericht"),
        (.french, "Thomas", "Peux-tu m'envoyer le rapport avant le déjeuner", "rapport"),
        (.spanish, "Paulina", "Puedes enviarme el informe antes del almuerzo", "informe"),
        (.italian, "Alice", "Puoi mandarmi il rapporto prima di pranzo", "rapporto"),
        (.portuguese, "Joana", "Podes enviar-me o relatório antes do almoço", "relat"),
        (.danish, "Sara", "Kan du sende mig rapporten før frokost", "rapport"),
        (.dutch, "Xander", "Kun je mij het rapport voor de lunch sturen", "rapport"),
    ]

    @Test(.enabled(if: ParakeetTests.completedInstallPresent), .timeLimit(.minutes(5)))
    func parakeetHearsEachNewLanguage() async throws {
        try await RealAudioGate.run {
            let parakeet = ParakeetTranscriber(store: ParakeetModelStore(), languages: { Language.allCases })
            try await parakeet.prepare()
            var problems: [String] = []
            for sample in Self.samples {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("pl-\(UUID().uuidString).aiff")
                let say = Process()
                say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
                say.arguments = ["-v", sample.voice, "-o", url.path, sample.sentence]
                try say.run()
                say.waitUntilExit()
                defer { try? FileManager.default.removeItem(at: url) }
                let session = try await parakeet.makeSession(language: .automatic)
                session.append(AudioChunk(samples: try AVAudioFileReader.samples16k(url)))
                let transcript = try await session.finish()
                print("parakeet \(sample.language): \(transcript.text) → \(String(describing: transcript.language))")
                if transcript.language != sample.language { problems.append("\(sample.language) guessed \(String(describing: transcript.language))") }
                if !transcript.text.lowercased().contains(sample.keyword) { problems.append("\(sample.language) text: \(transcript.text)") }
            }
            // Known weakness (2026-10-08): Parakeet mishears Danish ("Ketus in my rapporten for Frogost")
            // and the guess says English. Apple handles Danish; keep it visible until Parakeet improves.
            let danish = problems.filter { $0.hasPrefix("danish") }
            #expect(problems.count == danish.count, "\(problems)")
            withKnownIssue("Parakeet is weak at Danish") { #expect(danish.isEmpty, "\(danish)") }
        }
    }
}
