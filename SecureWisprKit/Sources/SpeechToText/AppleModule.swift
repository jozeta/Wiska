import Core
import Foundation
import Speech

/// One configured Apple speech module plus a way to collect its final results.
/// English uses SpeechTranscriber; Swedish uses DictationTranscriber (SpeechTranscriber has no sv_SE).
struct AppleModule {
    let language: Language
    let module: any SpeechModule
    let collect: @Sendable () async throws -> [AttributedString]

    static func make(_ language: Language) -> AppleModule {
        switch language {
        case .english:
            let module = SpeechTranscriber(
                locale: language.locale, transcriptionOptions: [], reportingOptions: [],
                attributeOptions: [.transcriptionConfidence]
            )
            let results = module.results
            return AppleModule(language: language, module: module) {
                var texts: [AttributedString] = []
                for try await result in results { texts.append(result.text) }
                return texts
            }
        case .swedish:
            let module = DictationTranscriber(
                locale: language.locale, contentHints: [.shortForm], transcriptionOptions: [.punctuation],
                reportingOptions: [], attributeOptions: [.transcriptionConfidence]
            )
            let results = module.results
            return AppleModule(language: language, module: module) {
                var texts: [AttributedString] = []
                for try await result in results { texts.append(result.text) }
                return texts
            }
        }
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
