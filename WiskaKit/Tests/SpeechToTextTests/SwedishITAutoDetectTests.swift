import Core
import Foundation
import Testing
@testable import SpeechToText

/// Swedish full of English IT words through Auto-detect (English + Swedish): which language wins,
/// what each side heard, and Apple's confidence. `WISKA_REAL_AUDIO=1 swift test --filter SwedishITAutoDetectTests`
@MainActor
struct SwedishITAutoDetectTests {
    static let sentences = [
        "Jag ska deploya den nya releasen till produktion efter att pull requesten har mergats.",
        "Vi har en bugg i backend, API:et returnerar fel när användaren loggar in med single sign-on.",
        "Kan du skapa en ticket i Jira och lägga den i nästa sprint?",
        "Servern i Azure behöver mer minne, så vi skalar upp Kubernetes-klustret.",
        "Jag pushade en fix till main-branchen, men pipelinen i GitHub Actions failade.",
        "Vi kör ett standup varje morgon och en retro efter varje sprint.",
        "Kolla loggarna i Datadog, det ser ut som en timeout mot databasen.",
        "Jag har ett stort hus och en liten trädgård.",
    ]

    @Test(.enabled(if: ProcessInfo.processInfo.environment["WISKA_REAL_AUDIO"] != nil), .timeLimit(.minutes(10)))
    func whichLanguageWins() async throws {
        for sentence in Self.sentences {
            let audio = try SpeechSamples.spoken(sentence, voice: "Alva")
            var heard: [Transcript] = []
            for language in [Language.english, .swedish] {
                let session = try await AppleTranscriber(languages: { [language] }).makeSession(language: .fixed(language))
                heard.append(try await SpeechSamples.transcribe(audio, with: session))
            }
            let picked = LanguagePicker.pick(heard, fallback: .english)
            print("AUTO picked \(picked.language?.rawValue ?? "?")")
            for transcript in heard {
                print(String(format: "AUTO   %@ %.2f | %@", transcript.language?.rawValue ?? "?", transcript.confidence ?? -1, transcript.text))
            }
        }
        await AppleTranscriber.release([.english, .swedish])
    }

    static let vocabulary = ["deploya", "deploy", "release", "releasen", "pull request", "pull requesten", "merge", "mergats",
                             "branch", "main-branchen", "commit", "pusha", "pushade", "backend", "frontend", "API", "API:et",
                             "single sign-on", "Azure", "Kubernetes", "Kubernetes-klustret", "Jira", "ticket", "sprint",
                             "pipeline", "pipelinen", "GitHub Actions", "failade", "standup", "retro", "Datadog", "timeout",
                             "server", "servern", "bugg"]

    @Test(.enabled(if: ProcessInfo.processInfo.environment["WISKA_REAL_AUDIO"] != nil), .timeLimit(.minutes(10)))
    func swedishWithAVocabulary() async throws {
        for sentence in Self.sentences {
            let audio = try SpeechSamples.spoken(sentence, voice: "Alva")
            for words in [[], Self.vocabulary] {
                let session = try await AppleTranscriber(languages: { [.swedish] }, vocabulary: { words })
                    .makeSession(language: .fixed(.swedish))
                let text = try await SpeechSamples.transcribe(audio, with: session).text
                print("VOCAB \(words.isEmpty ? "without" : "with   ") | \(text)")
            }
        }
        await AppleTranscriber.release([.swedish])
    }
}
