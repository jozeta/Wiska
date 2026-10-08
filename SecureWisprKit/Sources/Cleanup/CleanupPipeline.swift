import Core
import Foundation
import Synchronization

struct CleanupTimeout: Error {}

/// Commands → segments → model (guarded, time-boxed) → rule fallback.
@MainActor
public final class CleanupPipeline: TextCleaner {
    private static let log = Log.logger("Cleanup")
    static let shortSegmentWords = 3

    private let level: @MainActor () -> CleanupLevel
    private let rewriter: any TextRewriter
    private let timeout: Duration

    public init(level: @escaping @MainActor () -> CleanupLevel, rewriter: any TextRewriter,
                timeout: Duration = .milliseconds(1_500)) {
        self.level = level
        self.rewriter = rewriter
        self.timeout = timeout
    }

    public func prewarm() {
        let level = level()
        guard level != .off, rewriter.isAvailable else { return }
        rewriter.prewarm(level: level)
    }

    public func clean(_ text: String, context: DictationContext) async throws -> String {
        let level = level()
        let commanded = VoiceCommands.apply(text)
        guard level != .off else { return commanded }
        let deadline = ContinuousClock.now + timeout
        var cleaned: [String] = []
        for segment in commanded.components(separatedBy: "\n") {
            cleaned.append(await cleanSegment(segment, level: level, deadline: deadline))
        }
        return cleaned.joined(separator: "\n")
    }

    private func cleanSegment(_ raw: String, level: CleanupLevel, deadline: ContinuousClock.Instant) async -> String {
        let segment = raw.trimmingCharacters(in: .whitespaces)
        guard !segment.isEmpty else { return "" }
        let wordCount = segment.split(whereSeparator: \.isWhitespace).count
        guard wordCount > Self.shortSegmentWords, rewriter.isAvailable, ContinuousClock.now < deadline else {
            return RuleCleaner.clean(segment)
        }
        do {
            let output = Self.stripWrappingQuotes(try await rewrite(segment, level: level, deadline: deadline))
            switch CleanupGuard.check(original: segment, cleaned: output, level: level) {
            case .accept:
                return output
            case .reject(let reason):
                Self.log.notice("model output rejected: \(reason, privacy: .public)")
                return RuleCleaner.clean(segment)
            }
        } catch {
            Self.log.notice("model cleanup skipped: \(String(describing: error), privacy: .public)")
            return RuleCleaner.clean(segment)
        }
    }

    /// Races the model against the deadline without waiting for the model to honour
    /// cancellation: whichever finishes first resumes, the other is ignored.
    private func rewrite(_ segment: String, level: CleanupLevel,
                         deadline: ContinuousClock.Instant) async throws -> String {
        let rewriter = rewriter
        return try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            let work = Task { @MainActor in
                do { once.resume(.success(try await rewriter.rewrite(segment, level: level))) }
                catch { once.resume(.failure(error)) }
            }
            Task {
                try? await Task.sleep(until: deadline, clock: .continuous)
                once.resume(.failure(CleanupTimeout()))
                work.cancel()
            }
        }
    }

    static func stripWrappingQuotes(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let quotes: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("”", "”"), ("'", "'")]
        for (open, close) in quotes where result.count >= 2 && result.first == open && result.last == close {
            result = String(result.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }
}

/// Resumes a continuation exactly once, from whichever racer gets there first.
private final class ResumeOnce: Sendable {
    private let continuation: Mutex<CheckedContinuation<String, Error>?>

    init(_ continuation: CheckedContinuation<String, Error>) {
        self.continuation = Mutex(continuation)
    }

    func resume(_ result: Result<String, Error>) {
        continuation.withLock { pending in
            pending?.resume(with: result)
            pending = nil
        }
    }
}
