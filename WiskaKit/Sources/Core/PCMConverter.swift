import AVFoundation

public extension AVAudioFormat {
    /// The pipeline's canonical format: 16 kHz mono Float32, non-interleaved.
    static let speech16kMono = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: AudioChunk.sampleRate, channels: 1, interleaved: false
    )!
}

public extension AVAudioPCMBuffer {
    static func speech(samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: .speech16kMono, frameCapacity: AVAudioFrameCount(samples.count)
        ), let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }

    /// First channel as Float samples (empty for non-float formats).
    var floatSamples: [Float] {
        guard let channel = floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(frameLength)))
    }
}

/// Streaming sample-rate / channel / sample-format converter. Not thread-safe:
/// use each instance from one thread at a time (the audio tap, or the main actor).
public final class PCMConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let ratio: Double

    public init(from input: AVAudioFormat, to output: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: input, to: output) else {
            throw AudioError.unsupportedFormat
        }
        self.converter = converter
        self.outputFormat = output
        self.ratio = output.sampleRate / input.sampleRate
    }

    public func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw AudioError.unsupportedFormat
        }
        nonisolated(unsafe) var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        if let error { throw AudioError.engineFailed(error.localizedDescription) }
        return output
    }
}
