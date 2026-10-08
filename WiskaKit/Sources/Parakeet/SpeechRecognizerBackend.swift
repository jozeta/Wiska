import FluidAudio
import Foundation

/// The speech-to-text call Parakeet sessions need; FluidAudio in the app, a fake in tests.
public protocol SpeechRecognizerBackend: Sendable {
    func transcribe(_ samples: [Float]) async throws -> String
}

/// FluidAudio's Parakeet TDT v3 on the Neural Engine.
final class FluidAudioBackend: SpeechRecognizerBackend {
    private let manager: AsrManager

    init(manager: AsrManager) { self.manager = manager }

    static func load(from directory: URL) async throws -> FluidAudioBackend {
        let models = try await AsrModels.load(from: directory, version: .v3)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        return FluidAudioBackend(manager: manager)
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        var state = TdtDecoderState.make()
        return try await manager.transcribe(samples, decoderState: &state).text
    }
}
