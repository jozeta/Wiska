import Core
import Foundation
import Speech

/// One configured Apple speech module plus a way to collect its final results.
/// SpeechTranscriber where it has a model; DictationTranscriber for Swedish, Danish and Dutch.
struct AppleModule {
    let language: Language
    let module: any SpeechModule
    /// Collects finalized results; calls `progress` with the text so far (finalized + volatile).
    let collect: @Sendable (_ progress: @escaping @Sendable (String) -> Void) async throws -> [AttributedString]

    /// `volatile`: also report in-progress results, for the live preview.
    static func make(_ language: Language, volatile: Bool = false) -> AppleModule {
        if !language.usesDictationTranscriber {
            let module = SpeechTranscriber(
                locale: language.locale, transcriptionOptions: [],
                reportingOptions: volatile ? [.volatileResults] : [],
                attributeOptions: [.transcriptionConfidence]
            )
            let results = module.results
            return AppleModule(language: language, module: module) { progress in
                var finals: [AttributedString] = []
                for try await result in results {
                    if result.isFinal { finals.append(result.text) }
                    progress(AppleModule.text(finals, pending: result.isFinal ? nil : result.text))
                }
                return finals
            }
        } else {
            let module = DictationTranscriber(
                locale: language.locale, contentHints: [.shortForm], transcriptionOptions: [.punctuation],
                reportingOptions: volatile ? [.volatileResults] : [],
                attributeOptions: [.transcriptionConfidence]
            )
            let results = module.results
            // DictationTranscriber never marks results final (probed): each result restates its
            // segment from the segment's start, so the latest result per start time is the text.
            return AppleModule(language: language, module: module) { progress in
                var segments: [(start: Double, text: AttributedString)] = []
                for try await result in results {
                    let start = result.range.start.seconds
                    if let last = segments.indices.last, segments[last].start == start {
                        segments[last].text = result.text
                    } else {
                        segments.append((start, result.text))
                    }
                    progress(AppleModule.text(segments.map(\.text), pending: nil))
                }
                return segments.map(\.text)
            }
        }
    }

    /// Finalized text plus the segment still being heard, whitespace-normalized.
    static func text(_ finals: [AttributedString], pending: AttributedString?) -> String {
        summarize(finals + (pending.map { [$0] } ?? [])).text
    }

    /// Joined text and mean per-run confidence (nil if the model reported none).
    static func summarize(_ texts: [AttributedString]) -> (text: String, confidence: Double?) {
        let text = texts.map { String($0.characters) }
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        var confidences: [Double] = []
        for attributed in texts {
            for run in attributed.runs {
                if let confidence = run.transcriptionConfidence { confidences.append(confidence) }
            }
        }
        let mean = confidences.isEmpty ? nil : confidences.reduce(0, +) / Double(confidences.count)
        return (text, mean)
    }
}
