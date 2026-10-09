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
    private let style: @MainActor (AppCategory) -> WritingStyle
    private let snippets: @MainActor () -> [Snippet]
    private let grammar: @MainActor () -> Bool

    public init(level: @escaping @MainActor () -> CleanupLevel, rewriter: any TextRewriter,
                dictionary: @escaping @MainActor () -> PersonalDictionary = { PersonalDictionary() },
                isKnownWord: @escaping @MainActor (String) -> Bool = { _ in false },
                style: @escaping @MainActor (AppCategory) -> WritingStyle = { $0.defaultStyle ?? .formal },
                snippets: @escaping @MainActor () -> [Snippet] = { [] },
                grammar: @escaping @MainActor () -> Bool = { false },
                timeout: Duration = CleanupPipeline.defaultTimeout) {
        self.level = level
        self.rewriter = rewriter
        self.dictionary = dictionary
        self.isKnownWord = isKnownWord
        self.style = style
        self.snippets = snippets
        self.grammar = grammar
        self.timeout = timeout
    }

    public func prewarm() {
        let level = level()
        guard level != .off, rewriter.isAvailable else { return }
        rewriter.prewarm(level: level, grammar: grammar())
    }

    public func clean(_ text: String, context: DictationContext) async throws -> String {
        let level = level()
        let dictionary = dictionary()
        // The spoken language's words; all ticked languages' when the engine didn't say.
        let rules = context.language?.rules ?? LanguageRules.merged(context.enabledLanguages)
        let format = context.language?.formatRules ?? FormatRules.merged(context.enabledLanguages)
        // Snippets first: their text never passes through cleanup (placeholders stand in).
        let extracted = SnippetExpander.extract(VoiceCommands.apply(text, rules: rules), snippets: snippets())
        let slots = extracted.slots
        // The dictionary is spelling, not cleanup: it applies at every level.
        let corrected = DictionaryCorrector.apply(extracted.text, dictionary: dictionary, isKnownWord: isKnownWord)
        guard level != .off else { return SnippetExpander.fill(corrected, slots: slots) }
        // Code gets exactly what was said: no model, no fillers removed, no sentence shape.
        if context.category == .code {
            return SnippetExpander.fill(StyleFinisher.codeSafe(CodeVocabulary.apply(corrected), dictionary: dictionary),
                                        slots: slots)
        }
        let style = style(context.category)
        let grammar = grammar()
        let deadline = ContinuousClock.now + (rewriter.preferredTimeout ?? timeout)
        var lines: [FormattedLine] = []
        for segment in corrected.components(separatedBy: "\n") {
            if SnippetExpander.isPlaceholderLine(segment) {
                // A multi-line snippet's own line: nothing to clean.
                lines.append(FormattedLine(text: segment.trimmingCharacters(in: .whitespaces), isPlain: false))
                continue
            }
            let cleaned = await cleanSegment(segment, level: level, dictionary: dictionary, rules: rules,
                                             language: context.language, style: style, grammar: grammar, deadline: deadline)
            if let list = ListFormatter.format(cleaned, rules: format) {
                lines += list.map { FormattedLine(text: $0, isPlain: false) }
            } else {
                lines.append(FormattedLine(text: cleaned, isPlain: true))
            }
        }
        if context.category == .email { lines = EmailLayout.format(lines, rules: format) }
        let finished = lines.map { line in
            line.isPlain && !line.text.isEmpty
                ? StyleFinisher.finish(line.text, style: style, dictionary: dictionary) : line.text
        }.joined(separator: "\n")
        return SnippetExpander.fill(finished, slots: slots)
    }

    private func cleanSegment(_ raw: String, level: CleanupLevel, dictionary: PersonalDictionary,
                              rules: LanguageRules, language: Language?, style: WritingStyle,
                              grammar: Bool, deadline: ContinuousClock.Instant) async -> String {
        let segment = raw.trimmingCharacters(in: .whitespaces)
        guard !segment.isEmpty else { return "" }
        let wordCount = segment.split(whereSeparator: \.isWhitespace).count
        guard wordCount > Self.shortSegmentWords, rewriter.isAvailable, ContinuousClock.now < deadline else {
            return RuleCleaner.clean(segment, rules: rules)
        }
        do {
            // The segment is one line; line breaks only come from voice commands, not the model.
            let output = Self.stripWrappingQuotes(try await rewrite(segment, level: level, language: language, style: style, grammar: grammar, deadline: deadline))
                .split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: " ")
            switch CleanupGuard.check(original: segment, cleaned: output, level: level, rules: rules, grammar: grammar) {
            case .accept:
                // A model that lost or changed a snippet placeholder would lose the snippet.
                guard SnippetExpander.placeholders(in: output).isSuperset(of: SnippetExpander.placeholders(in: segment)) else {
                    Self.log.notice("model output rejected: snippet placeholder lost")
                    return RuleCleaner.clean(segment, rules: rules)
                }
                // The model never sees the dictionary; re-apply so it can't undo the user's spellings.
                return DictionaryCorrector.apply(output, dictionary: dictionary, isKnownWord: isKnownWord)
            case .reject(let reason):
                Self.log.notice("model output rejected: \(reason, privacy: .public)")
                return RuleCleaner.clean(segment, rules: rules)
            }
        } catch {
            // The type is enough to diagnose; the description may quote the dictated text.
            Self.log.notice("model cleanup skipped: \(String(describing: type(of: error)), privacy: .public) \(String(describing: error), privacy: .private)")
            return RuleCleaner.clean(segment, rules: rules)
        }
    }

    /// Races the model against the deadline without waiting for the model to honour
    /// cancellation: whichever finishes first resumes, the other is ignored.
    private func rewrite(_ segment: String, level: CleanupLevel, language: Language?, style: WritingStyle, grammar: Bool,
                         deadline: ContinuousClock.Instant) async throws -> String {
        let rewriter = rewriter
        return try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            let work = Task { @MainActor in
                do { once.resume(.success(try await rewriter.rewrite(segment, level: level, language: language, style: style, grammar: grammar))) }
                catch { once.resume(.failure(error)) }
            }
            Task {
                try? await Task.sleep(until: deadline, clock: .continuous)
                once.resume(.failure(CleanupTimeout()))
                work.cancel()
            }
        }
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
final class ResumeOnce: Sendable {
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
