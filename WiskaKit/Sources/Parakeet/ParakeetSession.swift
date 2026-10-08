import Core
import Foundation

/// Parakeet is batch: buffer the utterance, transcribe it on finish.
@MainActor
final class ParakeetSession: TranscriptionSession {
    /// FluidAudio needs at least one second of audio.
    static let minimumSamples = Int(AudioChunk.sampleRate)

    private let backend: any SpeechRecognizerBackend
    /// The ticked languages: the language guess chooses among these only.
    private let languages: [Language]
    private var samples: [Float] = []
    private var cancelled = false

    init(backend: any SpeechRecognizerBackend, languages: [Language] = Language.allCases) {
        self.backend = backend
        self.languages = languages
    }

    func append(_ chunk: AudioChunk) {
        guard !cancelled else { return }
        samples.append(contentsOf: chunk.samples)
    }

    func finish() async throws -> Transcript {
        guard !cancelled, !samples.isEmpty else {
            return Transcript(text: "", locale: Locale(identifier: "und"))
        }
        var audio = samples
        if audio.count < Self.minimumSamples {
            audio += Array(repeating: 0, count: Self.minimumSamples - audio.count)
        }
        let text = try await backend.transcribe(audio).trimmingCharacters(in: .whitespacesAndNewlines)
        let language = LanguageGuess.detect(text, among: languages)
        return Transcript(text: text, locale: language?.locale ?? Locale(identifier: "und"),
                          confidence: nil, language: language)
    }

    func cancel() {
        cancelled = true
        samples = []
    }
}
