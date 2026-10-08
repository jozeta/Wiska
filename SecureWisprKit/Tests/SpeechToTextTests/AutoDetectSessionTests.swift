import Core
import Foundation
import Testing
@testable import SpeechToText

struct StubError: Error {}

@MainActor
final class StubSession: TranscriptionSession {
    let outcome: Result<Transcript, StubError>
    private(set) var appended: [[Float]] = []
    private(set) var cancelled = false
    init(_ outcome: Result<Transcript, StubError>) { self.outcome = outcome }
    func append(_ chunk: AudioChunk) { appended.append(chunk.samples) }
    func finish() async throws -> Transcript { try outcome.get() }
    func cancel() { cancelled = true }
}

@MainActor
struct AutoDetectSessionTests {
    private func t(_ text: String, _ language: Language, _ confidence: Double) -> Transcript {
        Transcript(text: text, locale: language.locale, confidence: confidence, language: language)
    }

    @Test func fansOutAudioToEverySession() {
        let a = StubSession(.success(t("a", .english, 0.9)))
        let b = StubSession(.success(t("b", .swedish, 0.1)))
        let session = AutoDetectSession(sessions: [a, b], fallback: .english)
        session.append(AudioChunk(samples: [0.5]))
        #expect(a.appended == [[0.5]])
        #expect(b.appended == [[0.5]])
    }

    @Test func picksTheMoreConfidentLanguage() async throws {
        let session = AutoDetectSession(sessions: [
            StubSession(.success(t("can do we get up", .english, 0.40))),
            StubSession(.success(t("kan du skicka", .swedish, 0.78))),
        ], fallback: .english)
        #expect(try await session.finish().language == .swedish)
    }

    @Test func oneFailingBranchUsesTheOther() async throws {
        let session = AutoDetectSession(sessions: [
            StubSession(.failure(StubError())),
            StubSession(.success(t("kan du skicka", .swedish, 0.30))),
        ], fallback: .english)
        #expect(try await session.finish().language == .swedish)
    }

    @Test func allBranchesFailingThrows() async {
        let session = AutoDetectSession(sessions: [
            StubSession(.failure(StubError())), StubSession(.failure(StubError())),
        ], fallback: .english)
        await #expect(throws: StubError.self) { try await session.finish() }
    }

    @Test func cancelCancelsEverySession() {
        let a = StubSession(.success(t("a", .english, 0.9)))
        let b = StubSession(.success(t("b", .swedish, 0.9)))
        AutoDetectSession(sessions: [a, b], fallback: .english).cancel()
        #expect(a.cancelled && b.cancelled)
    }
}
