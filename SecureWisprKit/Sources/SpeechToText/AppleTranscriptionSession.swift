import AVFoundation
import Core
import Speech

/// One push-to-talk utterance streamed into a SpeechAnalyzer.
@MainActor
final class AppleTranscriptionSession: TranscriptionSession {
    private let locale: Locale
    private let analyzer: SpeechAnalyzer
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let converter: PCMConverter
    private let collector: Task<String, Error>

    private init(locale: Locale, analyzer: SpeechAnalyzer,
                 input: AsyncStream<AnalyzerInput>.Continuation,
                 converter: PCMConverter, collector: Task<String, Error>) {
        self.locale = locale
        self.analyzer = analyzer
        self.input = input
        self.converter = converter
        self.collector = collector
    }

    static func start(module: SpeechTranscriber, locale: Locale) async throws -> AppleTranscriptionSession {
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw TranscriptionError.noCompatibleAudioFormat
        }
        let analyzer = SpeechAnalyzer(modules: [module])
        try await analyzer.prepareToAnalyze(in: format)

        let results = module.results
        let collector = Task<String, Error> {
            var parts: [String] = []
            for try await result in results {
                parts.append(String(result.text.characters))
            }
            return parts.joined(separator: " ")
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
        }
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        try await analyzer.start(inputSequence: stream)
        return AppleTranscriptionSession(
            locale: locale, analyzer: analyzer, input: continuation,
            converter: try PCMConverter(from: .speech16kMono, to: format), collector: collector
        )
    }

    func append(_ chunk: AudioChunk) {
        guard let buffer = AVAudioPCMBuffer.speech(samples: chunk.samples),
              let converted = try? converter.convert(buffer) else { return }
        input.yield(AnalyzerInput(buffer: converted))
    }

    func finish() async throws -> Transcript {
        input.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        let text = try await collector.value
        return Transcript(text: text, locale: locale)
    }

    func cancel() {
        input.finish()
        collector.cancel()
        let analyzer = analyzer
        Task { await analyzer.cancelAndFinishNow() }
    }
}
