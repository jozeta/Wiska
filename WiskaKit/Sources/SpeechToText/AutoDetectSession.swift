import Core

/// Runs the same audio through one session per language and keeps the most confident result.
@MainActor
final class AutoDetectSession: TranscriptionSession {
    private static let log = Log.logger("SpeechToText")
    private let sessions: [any TranscriptionSession]
    private let fallback: Language
    private let previewIndex: Int

    init(sessions: [any TranscriptionSession], fallback: Language, previewIndex: Int = 0) {
        self.sessions = sessions
        self.fallback = fallback
        self.previewIndex = sessions.indices.contains(previewIndex) ? previewIndex : 0
    }

    /// One session's words: the language Wiska expects (the last one detected).
    var preview: AsyncStream<String> {
        sessions.isEmpty ? AsyncStream { $0.finish() } : sessions[previewIndex].preview
    }

    func append(_ chunk: AudioChunk) {
        for session in sessions { session.append(chunk) }
    }

    func finish() async throws -> Transcript {
        let outcomes = await withTaskGroup(of: Result<Transcript, any Error>.self) { group in
            for session in sessions {
                group.addTask {
                    do { return .success(try await session.finish()) } catch { return .failure(error) }
                }
            }
            var all: [Result<Transcript, any Error>] = []
            for await outcome in group { all.append(outcome) }
            return all
        }
        var transcripts: [Transcript] = []
        var firstError: (any Error)?
        for outcome in outcomes {
            switch outcome {
            case .success(let transcript): transcripts.append(transcript)
            case .failure(let error):
                Self.log.error("auto-detect branch failed: \(String(describing: error), privacy: .public)")
                firstError = firstError ?? error
            }
        }
        if transcripts.isEmpty, let firstError { throw firstError }
        return LanguagePicker.pick(transcripts, fallback: fallback)
    }

    func cancel() {
        for session in sessions { session.cancel() }
    }
}
