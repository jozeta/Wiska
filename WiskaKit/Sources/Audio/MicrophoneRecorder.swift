import AVFoundation
import Core

/// Captures the default input device, converted to 16 kHz mono, as an `AudioCapture`.
@MainActor
public final class MicrophoneRecorder: AudioSource {
    private static let log = Log.logger("Audio")

    private var engine = AVAudioEngine()
    private var chunkContinuation: AsyncStream<AudioChunk>.Continuation?
    private var levelContinuation: AsyncStream<AudioLevel>.Continuation?
    private var configObserver: NSObjectProtocol?
    private var restartsThisRecording = 0
    private static let maxRestartsPerRecording = 2

    public init() {
        observeConfigurationChanges()
    }

    public func start() throws -> AudioCapture {
        stop()
        let (chunks, chunkContinuation) = AsyncStream.makeStream(of: AudioChunk.self)
        let (levels, levelContinuation) = AsyncStream.makeStream(
            of: AudioLevel.self, bufferingPolicy: .bufferingNewest(32)
        )
        try startEngine(chunks: chunkContinuation, levels: levelContinuation)
        restartsThisRecording = 0
        self.chunkContinuation = chunkContinuation
        self.levelContinuation = levelContinuation
        return AudioCapture(chunks: chunks, levels: levels)
    }

    public func stop() {
        guard chunkContinuation != nil else { return }
        stopEngine()
        chunkContinuation?.finish()
        levelContinuation?.finish()
        chunkContinuation = nil
        levelContinuation = nil
    }

    /// A fresh engine per recording: an idle engine doesn't reliably learn about device
    /// changes (AirPods connecting while idle), and a stale input format makes installTap throw.
    private func startEngine(
        chunks: AsyncStream<AudioChunk>.Continuation, levels: AsyncStream<AudioLevel>.Continuation
    ) throws {
        engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioError.noInputDevice }

        let converter = try PCMConverter(from: format, to: .speech16kMono)
        input.installTap(
            onBus: 0, bufferSize: 1_024, format: format,
            block: Self.makeTapBlock(converter: converter, analyzer: SpectrumAnalyzer(), chunks: chunks,
                                     levels: levels)
        )
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw AudioError.engineFailed(error.localizedDescription)
        }
    }

    private func stopEngine() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    /// Built in a nonisolated context on purpose: the tap block runs on a realtime audio
    /// thread, and a closure formed inside this @MainActor class would inherit main-actor
    /// isolation and trap at runtime under Swift 6.
    private nonisolated static func makeTapBlock(
        converter: PCMConverter,
        analyzer: SpectrumAnalyzer,
        chunks: AsyncStream<AudioChunk>.Continuation,
        levels: AsyncStream<AudioLevel>.Continuation
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let converted = try? converter.convert(buffer) else { return }
            let samples = converted.floatSamples
            guard !samples.isEmpty else { return }
            chunks.yield(AudioChunk(samples: samples))
            for frame in analyzer.analyze(samples) { levels.yield(frame) }
        }
    }

    /// Device changes (AirPods connect, Bluetooth switching to its mic profile, mic unplugged)
    /// stop the engine. If we're recording, continue on the new device into the same streams;
    /// if that fails, end the capture so the controller transcribes what it has.
    private func observeConfigurationChanges() {
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main
        ) { [weak self] note in
            let source = note.object.map { ObjectIdentifier($0 as AnyObject) }
            MainActor.assumeIsolated {
                guard let self, source == ObjectIdentifier(self.engine),
                      let chunks = self.chunkContinuation,
                      let levels = self.levelContinuation else { return }
                guard self.restartsThisRecording < Self.maxRestartsPerRecording else {
                    Self.log.error("audio device kept changing; ending this recording")
                    self.stop()
                    return
                }
                self.restartsThisRecording += 1
                Self.log.notice("audio configuration changed mid-recording; restarting on new device")
                self.stopEngine()
                do {
                    try self.startEngine(chunks: chunks, levels: levels)
                } catch {
                    Self.log.error("could not restart audio: \(String(describing: error), privacy: .public)")
                    self.stop()
                }
            }
        }
    }
}
