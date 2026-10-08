import AVFoundation
import Testing
@testable import Core

struct PCMConverterTests {
    @Test func speechBufferRoundTripsSamples() throws {
        let samples: [Float] = [0, 0.25, -0.5, 1]
        let buffer = try #require(AVAudioPCMBuffer.speech(samples: samples))
        #expect(buffer.format.sampleRate == 16_000)
        #expect(buffer.format.channelCount == 1)
        #expect(buffer.floatSamples == samples)
    }

    @Test func downsamples48kStereoTo16kMono() throws {
        let input = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let converter = try PCMConverter(from: input, to: .speech16kMono)
        var total = 0
        for _ in 0..<10 {
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: input, frameCapacity: 4_800))
            buffer.frameLength = 4_800
            for channel in 0..<2 {
                let data = try #require(buffer.floatChannelData?[channel])
                for i in 0..<4_800 { data[i] = sin(Float(i) * 2 * .pi * 440 / 48_000) * 0.5 }
            }
            let out = try converter.convert(buffer)
            #expect(out.format.channelCount == 1)
            total += Int(out.frameLength)
        }
        // 1 s of 48 kHz in → ~16 000 frames out (converter keeps a little in its filter).
        #expect((15_680...16_000).contains(total))
    }
}
