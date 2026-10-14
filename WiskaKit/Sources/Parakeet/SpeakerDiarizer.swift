import Core
import Dispatch
import FluidAudio
import Foundation

/// Downloads FluidAudio's offline speaker diarization models (pyannote community-1 segmentation,
/// WeSpeaker voice embeddings and VBx clustering, about 21 MB) from Hugging Face; only while the
/// user's download runs is FluidAudio allowed online.
public struct DiarizerDownloader: ModelDownloader {
    public init() {}

    public func download(to directory: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        ModelHub.offlineMode = false
        defer { ModelHub.offlineMode = true }
        // FluidAudio writes into `<parent>/<repo folder>`, i.e. `directory`.
        _ = try await OfflineDiarizerModels.load(from: directory.deletingLastPathComponent(),
                                                 progressHandler: { progress($0.fractionCompleted) })
    }

    public func exists(at directory: URL) -> Bool {
        ModelNames.OfflineDiarizer.requiredModels.allSatisfy {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }
}

/// Tells the voices in a recording apart: who spoke when, on this Mac. Uses FluidAudio's offline
/// pipeline, which sees the whole recording at once: on real meetings (AMI) it puts about 3% of
/// speech under the wrong person, against about 29% for its streaming one.
public enum SpeakerDiarizer {
    /// Where the models live (FluidAudio writes into `<parent>/<repo folder>`).
    public nonisolated static var modelDirectory: URL {
        AppPaths.supportDirectory
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(Repo.diarizer.folderName, isDirectory: true)
    }

    public static let approximateSize = "21 MB"

    /// The voices in `samples` (16 kHz mono), as segments labelled by an opaque speaker id.
    /// `speakers`: how many people there are, when the user knows; the biggest help there is,
    /// as similar voices are otherwise easily taken for one.
    public static func segments(in samples: [Float], speakers: Int? = nil,
                                directory: URL = modelDirectory) async throws -> [VoiceSegmentData] {
        // Offline mode: from disk only.
        let models = try await OfflineDiarizerModels.load(from: directory.deletingLastPathComponent())
        var config = OfflineDiarizerConfig()
        config.clustering.numSpeakers = speakers
        let manager = OfflineDiarizerManager(config: config)
        manager.initialize(models: models)
        let result = try await manager.process(audio: samples)
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
