import Core
import Foundation

/// Parakeet picks the language itself, among 25, and sometimes hears a short English phrase as
/// Russian ("git status" → "Кит статус"). Every Wiska language is written in Latin letters, so
/// text in another alphabet is a misheard dictation: the same audio is re-transcribed by
/// `fallback` (Apple), which only knows the user's languages.
@MainActor
public final class ScriptFallbackTranscriber: Transcriber {
    static let log = Log.logger("Dictation")
    private let primary: any Transcriber
    private let fallback: any Transcriber

    public init(primary: any Transcriber, fallback: any Transcriber) {
        self.primary = primary
        self.fallback = fallback
    }

    public var isReady: Bool { primary.isReady }
    public var engine: SpeechEngine { primary.engine }
    public func isReady(for language: Language) -> Bool { primary.isReady(for: language) }
    public func isReady(for choice: LanguageChoice) -> Bool { primary.isReady(for: choice) }
    public func prepare() async throws { try await primary.prepare() }

    public func makeSession(language: LanguageChoice) async throws -> any TranscriptionSession {
        ScriptFallbackSession(primary: try await primary.makeSession(language: language), choice: language,
                              fallback: fallback)
    }

    /// True when the text has a letter outside the Latin alphabets (Cyrillic, Greek, CJK…).
    static func hasForeignLetters(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            scalar.properties.isAlphabetic && !latinRanges.contains { $0.contains(scalar.value) }
        }
    }

    private static let latinRanges: [ClosedRange<UInt32>] = [
        0x0041...0x024F,   // Basic Latin letters, Latin-1, Latin Extended-A/B
        0x0250...0x02AF,   // IPA extensions
        0x1E00...0x1EFF,   // Latin Extended Additional
    ]
}

@MainActor
final class ScriptFallbackSession: TranscriptionSession {
    private let primary: any TranscriptionSession
    private let choice: LanguageChoice
    private let fallback: any Transcriber
    private var chunks: [AudioChunk] = []

    init(primary: any TranscriptionSession, choice: LanguageChoice, fallback: any Transcriber) {
        self.primary = primary
        self.choice = choice
        self.fallback = fallback
    }

    var preview: AsyncStream<String> { primary.preview }

    func append(_ chunk: AudioChunk) {
        chunks.append(chunk)
        primary.append(chunk)
    }

    func finish() async throws -> Transcript {
        let transcript = try await primary.finish()
        guard ScriptFallbackTranscriber.hasForeignLetters(transcript.text), fallback.isReady(for: choice) else {
            return transcript
        }
        ScriptFallbackTranscriber.log.notice("heard another alphabet; re-transcribing with \(self.fallback.engine.rawValue, privacy: .public)")
        do {
            let session = try await fallback.makeSession(language: choice)
            for chunk in chunks { session.append(chunk) }
            var retry = try await session.finish()
            retry.engine = fallback.engine
            if retry.text.isEmpty { ScriptFallbackTranscriber.log.notice("re-transcription heard nothing; keeping the first") }
            return retry.text.isEmpty ? transcript : retry
        } catch {
            ScriptFallbackTranscriber.log.notice("re-transcription failed: \(Log.summary(error), privacy: .public); keeping the first")
            return transcript
        }
    }

    func cancel() {
        chunks = []
        primary.cancel()
    }
}
