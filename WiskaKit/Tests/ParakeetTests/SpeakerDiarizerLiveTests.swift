import AVFoundation
import Foundation
import Testing
@testable import Parakeet

/// Downloads the real models (~14 MB) into a temporary folder and tells two voices apart.
/// Opt-in: WISKA_LIVE_DIARIZATION=<folder with a1, b1, a2, b2 .aiff>.
struct SpeakerDiarizerLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WISKA_LIVE_DIARIZATION"] != nil))
    func twoVoicesAreToldApart() async throws {
        let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["WISKA_LIVE_DIARIZATION"]!)
        var samples: [Float] = []
        var expected: [(String, Double, Double)] = []
        for name in ["a1", "b1", "a2", "b2"] {
            let start = Double(samples.count) / 16_000
            samples += try load(folder.appendingPathComponent("\(name).aiff"))
            expected.append((String(name.prefix(1)), start, Double(samples.count) / 16_000))
            samples += [Float](repeating: 0, count: 8_000)   // half a second between turns
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("diarizer-\(UUID())")
            .appendingPathComponent("speaker-diarization-coreml")
        try await DiarizerDownloader().download(to: directory, progress: { _ in })
        let segments = try await SpeakerDiarizer.segments(in: samples, directory: directory)
        print("DIARIZATION", segments.map { "\($0.speaker) \(String(format: "%.1f–%.1f", $0.start, $0.end))" })
        // Each expected turn's middle is covered by one speaker; a's turns share one, b's the other.
        func speaker(at time: Double) -> String? { segments.first { $0.start <= time && time <= $0.end }?.speaker }
        let found = expected.map { speaker(at: ($0.1 + $0.2) / 2) }
        print("TURNS", found)
        #expect(found[0] != nil && found[0] == found[2])
        #expect(found[1] != nil && found[1] == found[3])
        #expect(found[0] != found[1])
    }

    func load(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let converter = AVAudioConverter(from: file.processingFormat, to: output)!
        let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: input)
        let result = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: AVAudioFrameCount(Double(file.length) * 16_000 / file.processingFormat.sampleRate) + 1_024)!
        var given = false
        _ = converter.convert(to: result, error: nil) { _, status in
            if given { status.pointee = .endOfStream; return nil }
            given = true
            status.pointee = .haveData
            return input
        }
        return Array(UnsafeBufferPointer(start: result.floatChannelData![0], count: Int(result.frameLength)))
    }
}
