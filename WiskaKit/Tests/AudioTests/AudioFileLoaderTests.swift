import AVFoundation
import Core
import Testing
@testable import Audio

struct AudioFileLoaderTests {
    /// Any rate and channel count comes back as 16 kHz mono.
    @Test func a44kStereoFileBecomes16kMono() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tone-\(UUID()).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 88_200)!
        buffer.frameLength = 88_200
        for channel in 0..<2 {
            for index in 0..<88_200 { buffer.floatChannelData![channel][index] = Float(sin(Double(index) * 0.03) * 0.5) }
        }
        try file.write(from: buffer)

        let samples = try AudioFileLoader.samples(from: url)
        #expect(abs(samples.count - 32_000) < 200, "\(samples.count)")   // 2 seconds
        #expect(samples.map(abs).max()! > 0.3)
    }

    @Test func aFileThatIsNotAudioThrows() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("notes-\(UUID()).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try "hello".write(to: url, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { try AudioFileLoader.samples(from: url) }
    }
}
