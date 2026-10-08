import AVFoundation
import Core
import Speech

/// One push-to-talk utterance streamed into a SpeechAnalyzer for one language.
@MainActor
final class AppleTranscriptionSession: TranscriptionSession {
    private let language: Language
    private let analyzer: SpeechAnalyzer
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let converter: PCMConverter
    private let collector: Task<[AttributedString], Error>

    private init(language: Language, analyzer: SpeechAnalyzer,
                 input: AsyncStream<AnalyzerInput>.Continuation,
                 converter: PCMConverter, collector: Task<[AttributedString], Error>) {
        self.language = language
        self.analyzer = analyzer
        self.input = input
        self.converter = converter
        self.collector = collector
    }

    static func start(language: Language, vocabulary: [String]) async throws -> AppleTranscriptionSession {
        let apple = AppleModule.make(language)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [apple.module]) else {
            throw TranscriptionError.noCompatibleAudioFormat
        }
        let analyzer = SpeechAnalyzer(modules: [apple.module])
        if !vocabulary.isEmpty {
            // Honoured by DictationTranscriber (Swedish); SpeechTranscriber ignores it (probed).
            let context = AnalysisContext()
            context.contextualStrings[.general] = vocabulary
            try await analyzer.setContext(context)
        }
        try await analyzer.prepareToAnalyze(in: format)

        let collector = Task<[AttributedString], Error> { try await apple.collect() }
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        do {
            try await analyzer.start(inputSequence: stream)
            return AppleTranscriptionSession(
                language: language, analyzer: analyzer, input: continuation,
                converter: try PCMConverter(from: .speech16kMono, to: format), collector: collector
            )
        } catch {
            // Don't leak the collector or the analyzer (minor a).
            continuation.finish()
            collector.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    func append(_ chunk: AudioChunk) {
        guard let buffer = AVAudioPCMBuffer.speech(samples: chunk.samples),
              let converted = try? converter.convert(buffer) else { return }
        input.yield(AnalyzerInput(buffer: converted))
    }

    func finish() async throws -> Transcript {
        input.finish()
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            cancel()   // minor a
            throw error
        }
        let summary = AppleModule.summarize(try await collector.value)
        return Transcript(text: summary.text, locale: language.locale,
                          confidence: summary.confidence, language: language)
    }

    func cancel() {
        input.finish()
        collector.cancel()
        let analyzer = analyzer
        Task { await analyzer.cancelAndFinishNow() }
    }
}
