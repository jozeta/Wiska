import Core
import Foundation
import Testing
@testable import Dictation

/// Hands each piece's sample count back as its "words", so the joined text shows how the file was cut.
@MainActor
private final class CountingSession: TranscriptionSession {
    private var count = 0
    func append(_ chunk: AudioChunk) { count += chunk.samples.count }
    func finish() async throws -> Transcript {
        Transcript(text: count == 0 ? "" : "n\(count)", locale: Language.swedish.locale, language: .swedish)
    }
    func cancel() {}
}

/// Pure sample math: off the main actor, so it never holds up the timing-sensitive controller tests.
struct FileTranscriptionCutTests {
    /// A tone with a quiet gap at `gap` seconds.
    func tone(seconds: Double, gapAt gap: Double) -> [Float] {
        let rate = AudioChunk.sampleRate
        return (0..<Int(seconds * rate)).map { index in
            let t = Double(index) / rate
            return abs(t - gap) < 0.2 ? 0 : Float(sin(t * 2 * .pi * 220) * 0.5)
        }
    }

    @Test func cutsFallInTheQuietNearTheTarget() {
        let samples = tone(seconds: 30, gapAt: 11.5)
        let cuts = FileTranscription.cuts(samples, every: 10, searching: 3)
        #expect(cuts.count == 2)   // ~11.5 s, then near 21.5 s
        let first = Double(cuts[0]) / AudioChunk.sampleRate
        #expect(abs(first - 11.5) < 0.2)
    }

    @Test func shortAudioIsOnePiece() {
        #expect(FileTranscription.cuts([Float](repeating: 0.1, count: 16_000), every: 10, searching: 3).isEmpty)
    }
}

@MainActor
struct FileTranscriptionTests {
    @Test func everyPieceIsTranscribedAndJoinedInOrder() async throws {
        var progress: [Double] = []
        let samples = [Float](repeating: 0.1, count: 25 * 16_000)
        let result = try await FileTranscription.run(samples, every: 10, searching: 3,
                                                     session: { CountingSession() },
                                                     progress: { progress.append($0) })
        let pieces = result.text.split(separator: " ").map { Int($0.dropFirst())! }
        #expect(pieces.reduce(0, +) == samples.count)
        #expect(pieces.count == 3)
        #expect(result.language == .swedish)
        #expect(progress.last == 1)
        #expect(progress == progress.sorted())
    }

    @Test func silentPiecesAddNothing() async throws {
        let result = try await FileTranscription.run([], every: 10, searching: 3,
                                                     session: { CountingSession() }, progress: { _ in })
        #expect(result.text.isEmpty)
    }
}
