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
    let preview: AsyncStream<String>

    private init(language: Language, analyzer: SpeechAnalyzer,
                 input: AsyncStream<AnalyzerInput>.Continuation,
                 converter: PCMConverter, collector: Task<[AttributedString], Error>,
                 preview: AsyncStream<String>) {
        self.preview = preview
        self.language = language
        self.analyzer = analyzer
        self.input = input
        self.converter = converter
        self.collector = collector
    }

    static func start(language: Language, vocabulary: [String],
                      volatile: Bool = false) async throws -> AppleTranscriptionSession {
        let apple = AppleModule.make(language, volatile: volatile)
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

        // Only the newest text matters to the HUD: older previews are dropped if it lags behind.
        let (preview, previewInput) = AsyncStream.makeStream(of: String.self,
                                                             bufferingPolicy: .bufferingNewest(1))
        let collector = Task<[AttributedString], Error> {
            defer { previewInput.finish() }
            return try await apple.collect { previewInput.yield($0) }
        }
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        do {
            try await analyzer.start(inputSequence: stream)
            return AppleTranscriptionSession(
                language: language, analyzer: analyzer, input: continuation,
                converter: try PCMConverter(from: .speech16kMono, to: format), collector: collector,
                preview: preview
            )
        } catch {
            // Don't leak the collector or the analyzer (minor a).
            continuation.finish()
            previewInput.finish()
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
