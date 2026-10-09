import AVFoundation
import Core
import Foundation
import Speech
import Testing
@testable import SpeechToText

@MainActor
struct AppleTranscriberTests {
    private func spokenSamples(_ text: String, voice: String = "Samantha") throws -> [Float] {
        try SpeechSamples.spoken(text, voice: voice)
    }

    @Test(.enabled(if: SpeechTranscriber.isAvailable), .timeLimit(.minutes(2)))
    func transcribesSpokenEnglish() async throws {
        let samples = try spokenSamples("hello world this is a test")
        let transcriber = AppleTranscriber()
        let session = try await transcriber.makeSession(language: .fixed(.english))
        // Feed in 100 ms chunks, like the microphone does.
        for start in stride(from: 0, to: samples.count, by: 1_600) {
            session.append(AudioChunk(samples: Array(samples[start..<min(start + 1_600, samples.count)])))
        }
        let transcript = try await session.finish()
        // SpeechTranscriber punctuates ("Hello, world, this is a test."), so compare letters only.
        let words = transcript.text.lowercased().filter { $0.isLetter || $0 == " " }
        #expect(words.contains("hello world this is a test"))
        #expect(transcript.locale.identifier.hasPrefix("en"))
    }

    @Test(.enabled(if: SpeechTranscriber.isAvailable), .timeLimit(.minutes(1)))
    func silenceGivesEmptyText() async throws {
        let session = try await AppleTranscriber().makeSession(language: .fixed(.english))
        session.append(AudioChunk(samples: Array(repeating: 0, count: 16_000)))
        let transcript = try await session.finish()
        #expect(transcript.text.isEmpty)
    }

    private func transcribe(_ samples: [Float], _ choice: LanguageChoice,
                            transcriber: AppleTranscriber = AppleTranscriber()) async throws -> Transcript {
        let session = try await transcriber.makeSession(language: choice)
        for start in stride(from: 0, to: samples.count, by: 1_600) {
            session.append(AudioChunk(samples: Array(samples[start..<min(start + 1_600, samples.count)])))
        }
        return try await session.finish()
    }

    @Test(.timeLimit(.minutes(2)))
    func livePreviewShowsWordsBeforeTheFinalText() async throws {
        let samples = try spokenSamples("Can you send me the quarterly report before lunch tomorrow")
        let session = try await AppleTranscriber(languages: { [.english] }, livePreview: { true })
            .makeSession(language: .fixed(.english))
        let previews = Task { @MainActor in
            var seen: [String] = []
            for await text in session.preview { seen.append(text) }
            return seen
        }
        for start in stride(from: 0, to: samples.count, by: 1_600) {
            session.append(AudioChunk(samples: Array(samples[start..<min(start + 1_600, samples.count)])))
            try await Task.sleep(for: .milliseconds(20))
        }
        let transcript = try await session.finish()
        let seen = await previews.value
        #expect(seen.count >= 2, "previews: \(seen)")
        let heardWords = seen.contains { !$0.isEmpty }
        #expect(heardWords)
        #expect(transcript.text.lowercased().contains("quarterly report"))
    }

    /// Swedish runs on DictationTranscriber, which never marks results final.
    @Test(.timeLimit(.minutes(2)))
    func swedishLivePreviewGrowsAndTheFinalTextSurvives() async throws {
        let samples = try spokenSamples("Kan du skicka rapporten till mig innan lunch imorgon", voice: "Alva")
        let session = try await AppleTranscriber(languages: { [.swedish] }, livePreview: { true })
            .makeSession(language: .fixed(.swedish))
        let previews = Task { @MainActor in
            var seen: [String] = []
            for await text in session.preview { seen.append(text) }
            return seen
        }
        for start in stride(from: 0, to: samples.count, by: 1_600) {
            session.append(AudioChunk(samples: Array(samples[start..<min(start + 1_600, samples.count)])))
            try await Task.sleep(for: .milliseconds(20))
        }
        let transcript = try await session.finish()
        let seen = await previews.value
        #expect(seen.count >= 2, "previews: \(seen)")
        #expect(transcript.text.lowercased().contains("rapporten"))
    }

    @Test(.timeLimit(.minutes(1)))
    func previewOffYieldsOnlyFinishedSegments() async throws {
        let session = try await AppleTranscriber(languages: { [.english] }, livePreview: { false })
            .makeSession(language: .fixed(.english))
        session.append(AudioChunk(samples: Array(repeating: 0, count: 16_000)))
        _ = try await session.finish()
        var seen: [String] = []
        for await text in session.preview { seen.append(text) }
        let allEmpty = seen.allSatisfy(\.isEmpty)
        #expect(allEmpty, "previews: \(seen)")
    }

    @Test(.timeLimit(.minutes(2)))
    func transcribesSpokenSwedish() async throws {
        let samples = try spokenSamples("Kan du skicka rapporten till mig innan lunch imorgon", voice: "Alva")
        let transcript = try await transcribe(samples, .fixed(.swedish))
        #expect(transcript.text.lowercased().contains("rapporten"))
        #expect(transcript.language == .swedish)
        #expect(transcript.locale.identifier == "sv_SE")
        #expect((transcript.confidence ?? 0) > 0.5)
    }

    @Test(.timeLimit(.minutes(2)))
    func englishTranscriptCarriesConfidenceAndLanguage() async throws {
        let samples = try spokenSamples("Can you send me the quarterly report before lunch tomorrow")
        let transcript = try await transcribe(samples, .fixed(.english))
        #expect(transcript.language == .english)
        #expect((transcript.confidence ?? 0) > 0.5)
    }

    @Test func transcriberIsReadyOnlyAfterBothLanguagesPrepared() async throws {
        let transcriber = AppleTranscriber()
        #expect(!transcriber.isReady)
        try await transcriber.prepare()
        #expect(transcriber.isReady)
    }

    @Test(.timeLimit(.minutes(2)))
    func autoDetectPicksEnglishForEnglishSpeech() async throws {
        let samples = try spokenSamples("Can you send me the quarterly report before lunch tomorrow")
        let transcript = try await transcribe(samples, .automatic,
                                              transcriber: AppleTranscriber(fallbackLanguage: { .swedish }))
        #expect(transcript.language == .english)
        #expect(transcript.text.lowercased().contains("quarterly report"))
    }

    @Test(.timeLimit(.minutes(2)))
    func autoDetectPicksSwedishForSwedishSpeech() async throws {
        let samples = try spokenSamples("Kan du skicka rapporten till mig innan lunch imorgon", voice: "Alva")
        let transcript = try await transcribe(samples, .automatic,
                                              transcriber: AppleTranscriber(fallbackLanguage: { .english }))
        #expect(transcript.language == .swedish)
        #expect(transcript.text.lowercased().contains("rapporten"))
    }

    @Test(.timeLimit(.minutes(2)))
    func englishStillWorksWhenSwedishAssetsFailToInstall() async throws {
        // Review I3: a failed sv_SE install must not break English dictation.
        let transcriber = AppleTranscriber(installer: { language in
            if language == .swedish { throw TranscriptionError.unsupportedLocale("sv_SE") }
            try await AppleTranscriber.installAssets(for: language)
        })
        let samples = try spokenSamples("hello world this is a test")
        let transcript = try await transcribe(samples, .fixed(.english), transcriber: transcriber)
        #expect(transcript.language == .english)
        #expect(!transcriber.isReady)   // "ready" still means both languages
    }

    @Test(.timeLimit(.minutes(2)))
    func autoDetectFallsBackToTheLanguageThatStarts() async throws {
        let transcriber = AppleTranscriber(fallbackLanguage: { .swedish }, installer: { language in
            if language == .swedish { throw TranscriptionError.unsupportedLocale("sv_SE") }
            try await AppleTranscriber.installAssets(for: language)
        })
        let samples = try spokenSamples("hello world this is a test")
        let transcript = try await transcribe(samples, .automatic, transcriber: transcriber)
        #expect(transcript.language == .english)
    }

    @Test func autoDetectFailsOnlyWhenNoLanguageStarts() async throws {
        let transcriber = AppleTranscriber(installer: { language in
            throw TranscriptionError.unsupportedLocale(language.rawValue)
        })
        await #expect(throws: TranscriptionError.self) {
            _ = try await transcriber.makeSession(language: .automatic)
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func swedishUsesTheDictionaryAsHints() async throws {
        let samples = try spokenSamples("Skicka rapporten om Kvarnholmen till Ylva Zetterström och Jozeta",
                                        voice: "Alva")
        let transcriber = AppleTranscriber(vocabulary: { ["Kvarnholmen", "Ylva Zetterström", "Jozeta"] })
        let transcript = try await transcribe(samples, .fixed(.swedish), transcriber: transcriber)
        #expect(transcript.text.contains("Jozeta"), "\(transcript.text)")
        #expect(transcriber.engine == .apple)
    }

    @Test func prepareInstallsOnlyTickedLanguages() async throws {
        var installed: [Language] = []
        let transcriber = AppleTranscriber(languages: { [.english, .german] }, installer: { installed.append($0) })
        try await transcriber.prepare()
        #expect(installed == [.english, .german])
        #expect(transcriber.isReady)
    }

    @Test func automaticWithOneLanguageStartsOneSession() async throws {
        let transcriber = AppleTranscriber(languages: { [.english] })
        let session = try await transcriber.makeSession(language: .automatic)
        #expect(!(session is AutoDetectSession))
        session.cancel()
    }

    @Test func installedLanguagesStayReadyWhileAnotherFails() async throws {
        let transcriber = AppleTranscriber(languages: { [.english, .german] }, installer: { language in
            if language == .german { throw TranscriptionError.unsupportedLocale("de_DE") }
        })
        try? await transcriber.prepare()
        #expect(!transcriber.isReady)
        #expect(transcriber.isReady(for: .fixed(.english)))
        #expect(!transcriber.isReady(for: .fixed(.german)))
        #expect(transcriber.isReady(for: .automatic))
        #expect(transcriber.installErrors[.german] != nil)
        #expect(transcriber.installErrors[.english] == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func autoDetectDoesNotWaitForADownloadingLanguage() async throws {
        let transcriber = AppleTranscriber(languages: { [.english, .german] }, installer: { language in
            if language == .german { try await Task.sleep(for: .seconds(20)) }
        })
        try await transcriber.makeSession(language: .fixed(.english)).cancel()   // English installed
        let start = ContinuousClock.now
        let session = try await transcriber.makeSession(language: .automatic)
        #expect(ContinuousClock.now - start < .seconds(5))
        #expect(!(session is AutoDetectSession))   // English only, until German arrives
        session.cancel()
    }
}
