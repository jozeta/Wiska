import Core
import Dispatch
import FluidAudio
import Foundation

/// Downloads FluidAudio's speaker diarization models (pyannote segmentation and WeSpeaker voice
/// embeddings, about 14 MB) from Hugging Face; only while the user's download runs is FluidAudio
/// allowed online.
public struct DiarizerDownloader: ModelDownloader {
    public init() {}

    public func download(to directory: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        ModelHub.offlineMode = false
        defer { ModelHub.offlineMode = true }
        _ = try await DiarizerModels.download(to: directory, progressHandler: { progress($0.fractionCompleted) })
    }

    public func exists(at directory: URL) -> Bool {
        DiarizerModels.requiredModelNames.allSatisfy {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }
}

/// Tells the voices in a recording apart: who spoke when, on this Mac.
public enum SpeakerDiarizer {
    /// Where the models live (FluidAudio writes into `<parent>/<repo folder>`).
    public nonisolated static var modelDirectory: URL {
        AppPaths.supportDirectory
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(Repo.diarizer.folderName, isDirectory: true)
    }

    public static let approximateSize = "14 MB"

    /// The voices in `samples` (16 kHz mono), as segments labelled by an opaque speaker id.
    public static func segments(in samples: [Float], directory: URL = modelDirectory) async throws -> [VoiceSegmentData] {
        let models = try await DiarizerModels.load(from: directory)   // offline: from disk only
        nonisolated(unsafe) let manager = DiarizerManager()
        manager.initialize(models: models)
        let result = try await runBlocking { try manager.performCompleteDiarization(samples) }
        manager.cleanup()
        return result.segments.map {
            VoiceSegmentData(speaker: $0.speakerId, start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds))
        }
    }
}

/// Plain data, so the app needn't import FluidAudio.
public struct VoiceSegmentData: Sendable, Equatable {
    public let speaker: String
    public let start: Double
    public let end: Double
}
