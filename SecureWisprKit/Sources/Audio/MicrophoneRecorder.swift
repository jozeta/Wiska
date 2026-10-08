import AVFoundation
import Core

/// Captures the default input device, converted to 16 kHz mono, as an `AudioCapture`.
@MainActor
public final class MicrophoneRecorder: AudioSource {
    private static let log = Log.logger("Audio")

    private var engine = AVAudioEngine()
    private var chunkContinuation: AsyncStream<AudioChunk>.Continuation?
    private var levelContinuation: AsyncStream<Float>.Continuation?
    private var configObserver: NSObjectProtocol?

    public init() {
        observeConfigurationChanges()
    }

    public func start() throws -> AudioCapture {
        stop()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioError.noInputDevice }

        let converter = try PCMConverter(from: format, to: .speech16kMono)
        let (chunks, chunkContinuation) = AsyncStream.makeStream(of: AudioChunk.self)
        let (levels, levelContinuation) = AsyncStream.makeStream(
            of: Float.self, bufferingPolicy: .bufferingNewest(8)
        )
        input.installTap(
            onBus: 0, bufferSize: 1_024, format: format,
            block: Self.makeTapBlock(converter: converter, chunks: chunkContinuation, levels: levelContinuation)
        )
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw AudioError.engineFailed(error.localizedDescription)
        }
        self.chunkContinuation = chunkContinuation
        self.levelContinuation = levelContinuation
        return AudioCapture(chunks: chunks, levels: levels)
    }

    public func stop() {
        guard chunkContinuation != nil else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        chunkContinuation?.finish()
        levelContinuation?.finish()
        chunkContinuation = nil
        levelContinuation = nil
    }

    /// Built in a nonisolated context on purpose: the tap block runs on a realtime audio
    /// thread, and a closure formed inside this @MainActor class would inherit main-actor
    /// isolation and trap at runtime under Swift 6.
    private nonisolated static func makeTapBlock(
        converter: PCMConverter,
        chunks: AsyncStream<AudioChunk>.Continuation,
        levels: AsyncStream<Float>.Continuation
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let converted = try? converter.convert(buffer) else { return }
            let samples = converted.floatSamples
            guard !samples.isEmpty else { return }
            chunks.yield(AudioChunk(samples: samples))
            levels.yield(Levels.normalized(rms: Levels.rms(samples)))
        }
    }

    /// Device changes (AirPods connect, mic unplugged) invalidate the engine's format.
    /// End the current capture with what we have and rebuild the engine for next time.
    private func observeConfigurationChanges() {
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Self.log.notice("audio configuration changed; rebuilding engine")
                self.stop()
                self.engine = AVAudioEngine()
            }
        }
    }
}
