import Core
import Foundation
import Synchronization

struct CleanupTimeout: Error {}

/// Commands → segments → model (guarded, time-boxed) → rule fallback.
@MainActor
public final class CleanupPipeline: TextCleaner {
    private static let log = Log.logger("Cleanup")
    static let shortSegmentWords = 3
    /// Release→paste must stay under 1.5 s; after the 150 ms release tail and transcription,
    /// cleanup gets at most 1 s (review I3).
    public static let defaultTimeout: Duration = .milliseconds(1_000)

    private let level: @MainActor () -> CleanupLevel
    private let rewriter: any TextRewriter
    private let timeout: Duration
    private let dictionary: @MainActor () -> PersonalDictionary
    private let isKnownWord: @MainActor (String) -> Bool

    public init(level: @escaping @MainActor () -> CleanupLevel, rewriter: any TextRewriter,
                dictionary: @escaping @MainActor () -> PersonalDictionary = { PersonalDictionary() },
                isKnownWord: @escaping @MainActor (String) -> Bool = { _ in false },
                timeout: Duration = CleanupPipeline.defaultTimeout) {
        self.level = level
        self.rewriter = rewriter
        self.dictionary = dictionary
        self.isKnownWord = isKnownWord
        self.timeout = timeout
    }

    public func prewarm() {
        let level = level()
        guard level != .off, rewriter.isAvailable else { return }
        rewriter.prewarm(level: level)
    }

    public func clean(_ text: String, context: DictationContext) async throws -> String {
        let level = level()
        let dictionary = dictionary()
        // The dictionary is spelling, not cleanup: it applies at every level.
        let corrected = DictionaryCorrector.apply(VoiceCommands.apply(text), dictionary: dictionary,
                                                  isKnownWord: isKnownWord)
        guard level != .off else { return corrected }
        let deadline = ContinuousClock.now + timeout
        var cleaned: [String] = []
        for segment in corrected.components(separatedBy: "\n") {
            cleaned.append(await cleanSegment(segment, level: level, dictionary: dictionary, deadline: deadline))
        }
        return cleaned.joined(separator: "\n")
    }

    private func cleanSegment(_ raw: String, level: CleanupLevel, dictionary: PersonalDictionary,
                              deadline: ContinuousClock.Instant) async -> String {
        let segment = raw.trimmingCharacters(in: .whitespaces)
        guard !segment.isEmpty else { return "" }
        let wordCount = segment.split(whereSeparator: \.isWhitespace).count
        guard wordCount > Self.shortSegmentWords, rewriter.isAvailable, ContinuousClock.now < deadline else {
            return RuleCleaner.clean(segment)
        }
        do {
            // The segment is one line; line breaks only come from voice commands, not the model.
            let output = Self.stripWrappingQuotes(try await rewrite(segment, level: level, deadline: deadline))
                .split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: " ")
            switch CleanupGuard.check(original: segment, cleaned: output, level: level) {
            case .accept:
                // The model never sees the dictionary; re-apply so it can't undo the user's spellings.
                return Self.finishSentence(DictionaryCorrector.apply(output, dictionary: dictionary,
                                                                           isKnownWord: isKnownWord))
            case .reject(let reason):
                Self.log.notice("model output rejected: \(reason, privacy: .public)")
                return RuleCleaner.clean(segment)
            }
        } catch {
            // The type is enough to diagnose; the description may quote the dictated text.
            Self.log.notice("model cleanup skipped: \(String(describing: type(of: error)), privacy: .public) \(String(describing: error), privacy: .private)")
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

    /// The model sometimes skips punctuation; make accepted output look typed (review I5).
    static func finishSentence(_ text: String) -> String {
        guard let first = text.first else { return text }
        var result = first.uppercased() + text.dropFirst()
        // Look past closing quotes and brackets: `"see you soon."` already ends a sentence.
        let closers: Set<Character> = ["\"", "”", "'", "’", ")"]
        if let last = result.last(where: { !closers.contains($0) }), !".?!…:".contains(last) { result += "." }
        return result
    }

    /// Removes quotes the model wrapped its whole answer in, but not real quotations:
    /// if the inside has quote marks of its own, the outer ones belong to the text.
    static func stripWrappingQuotes(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let quotes: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("”", "”"), ("'", "'")]
        for (open, close) in quotes where result.count >= 2 && result.first == open && result.last == close {
            let inner = result.dropFirst().dropLast()
            guard !inner.contains(open), !inner.contains(close) else { continue }
            result = String(inner).trimmingCharacters(in: .whitespacesAndNewlines)
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
