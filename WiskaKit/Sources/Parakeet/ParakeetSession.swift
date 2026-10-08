import Core
import Foundation

/// Parakeet is batch: buffer the utterance, transcribe it on finish.
@MainActor
final class ParakeetSession: TranscriptionSession {
    /// FluidAudio needs at least one second of audio.
    static let minimumSamples = Int(AudioChunk.sampleRate)

    private let backend: any SpeechRecognizerBackend
    private var samples: [Float] = []
    private var cancelled = false

    init(backend: any SpeechRecognizerBackend) {
        self.backend = backend
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
        let language = LanguageGuess.detect(text)
        return Transcript(text: text, locale: language?.locale ?? Locale(identifier: "und"),
                          confidence: nil, language: language)
    }

    func cancel() {
        cancelled = true
        samples = []
    }
}
