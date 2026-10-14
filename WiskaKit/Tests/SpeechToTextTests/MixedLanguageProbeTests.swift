import AVFoundation
import Core
import Foundation
import Speech
import Testing
@testable import SpeechToText

/// Probe: per-word time and confidence from Apple's Swedish and English recognisers on the same
/// Swedish-with-English-IT-words audio. `WISKA_REAL_AUDIO=1 swift test --filter MixedLanguageProbeTests`
@MainActor
struct MixedLanguageProbeTests {
    struct Word { let text: String; let start: Double; let end: Double; let confidence: Double }

    static func words(_ audio: [Float], _ language: Language, vocabulary: [String] = []) async throws -> [Word] {
        let module: any SpeechModule
        let results: AsyncThrowingStream<(AttributedString, Double), Error>
        if language.usesDictationTranscriber {
            let dictation = DictationTranscriber(locale: language.locale, contentHints: [.shortForm],
                                                 transcriptionOptions: [.punctuation], reportingOptions: [],
                                                 attributeOptions: [.transcriptionConfidence, .audioTimeRange])
            module = dictation
            results = AsyncThrowingStream { continuation in
                Task { do { for try await r in dictation.results { continuation.yield((r.text, r.range.start.seconds)) }; continuation.finish() } catch { continuation.finish(throwing: error) } }
            }
        } else {
            let speech = SpeechTranscriber(locale: language.locale, transcriptionOptions: [], reportingOptions: [],
                                           attributeOptions: [.transcriptionConfidence, .audioTimeRange])
            module = speech
            results = AsyncThrowingStream { continuation in
                Task { do { for try await r in speech.results where r.isFinal { continuation.yield((r.text, r.range.start.seconds)) }; continuation.finish() } catch { continuation.finish(throwing: error) } }
            }
        }
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module])!
        let analyzer = SpeechAnalyzer(modules: [module])
        if !vocabulary.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = vocabulary
            try await analyzer.setContext(context)
        }
        try await analyzer.prepareToAnalyze(in: format)
        let (stream, input) = AsyncStream.makeStream(of: AnalyzerInput.self)
        try await analyzer.start(inputSequence: stream)
        let converter = try PCMConverter(from: .speech16kMono, to: format)
        for start in stride(from: 0, to: audio.count, by: 1_600) {
            let buffer = AVAudioPCMBuffer.speech(samples: Array(audio[start..<min(start + 1_600, audio.count)]))!
            input.yield(AnalyzerInput(buffer: try converter.convert(buffer)))
        }
        input.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        var latest: [Double: AttributedString] = [:]
        for try await (text, start) in results { latest[start] = text }   // Dictation restates segments
        var words: [Word] = []
        for start in latest.keys.sorted() {
            let text = latest[start]!
            for run in text.runs {
                let piece = String(text[run.range].characters).trimmingCharacters(in: .whitespaces)
                guard !piece.isEmpty else { continue }
                let range = run.audioTimeRange
                words.append(Word(text: piece, start: range?.start.seconds ?? -1, end: range?.end.seconds ?? -1,
                                  confidence: run.transcriptionConfidence ?? -1))
            }
        }
        return words
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["WISKA_REAL_AUDIO"] != nil), .timeLimit(.minutes(10)))
    func probe() async throws {
        for sentence in SwedishITAutoDetectTests.sentences.prefix(5) {
            let audio = try SpeechSamples.spoken(sentence, voice: "Alva")
            print("PROBE ===", sentence)
            for language in [Language.swedish, .english] {
                let words = try await Self.words(audio, language)
                print("PROBE \(language.rawValue): " + words.map { String(format: "%@[%.1f–%.1f %.2f]", $0.text, $0.start, $0.end, $0.confidence) }.joined(separator: " "))
            }
        }
        await AppleTranscriber.release([.english, .swedish])
    }

    /// Doubtful Swedish words (low confidence), merged when adjacent, each cut out with a little
    /// margin and heard again by English alone.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WISKA_REAL_AUDIO"] != nil), .timeLimit(.minutes(10)))
    func doubtfulStretchesHeardAgainInEnglish() async throws {
        for sentence in SwedishITAutoDetectTests.sentences {
            let audio = try SpeechSamples.spoken(sentence, voice: "Alva")
            let swedish = try await Self.words(audio, .swedish).filter { $0.text.contains { $0.isLetter } }
            print("CLIP ===", sentence)
            print("CLIP sv:", swedish.map(\.text).joined(separator: " "))
            var stretches: [(words: [Word], start: Double, end: Double)] = []
            for (index, word) in swedish.enumerated() where word.confidence < 0.35 {
                if let last = stretches.last, last.words.last.map({ w in swedish.firstIndex { $0.start == w.start } == index - 1 }) == true {
                    stretches[stretches.count - 1].words.append(word)
                    stretches[stretches.count - 1].end = word.end
                } else {
                    stretches.append(([word], word.start, word.end))
                }
            }
            for stretch in stretches {
                let from = max(0, Int((stretch.start - 0.15) * 16_000))
                let to = min(audio.count, Int((stretch.end + 0.15) * 16_000))
                let clip = Array(audio[from..<to]) + [Float](repeating: 0, count: 8_000)
                let english = try await Self.words(clip, .english)
                let heard = english.map { String(format: "%@ %.2f", $0.text, $0.confidence) }.joined(separator: " ")
                print("CLIP   \(stretch.words.map(\.text).joined(separator: " ")) → \(heard)")
            }
        }
        await AppleTranscriber.release([.english, .swedish])
    }
}
