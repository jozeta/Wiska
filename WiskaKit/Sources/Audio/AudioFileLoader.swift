import AVFoundation
import Core

/// Reads an audio file (anything Core Audio opens: m4a, mp3, wav, caf, aiff…) as the pipeline's
/// 16 kHz mono samples. Synchronous: call it off the main thread.
public enum AudioFileLoader {
    public enum LoadError: Error, Equatable {
        /// Longer than `maxSeconds`.
        case tooLong
    }

    /// Up to three hours by default (about 700 MB of samples).
    public static func samples(from url: URL, maxSeconds: Double = 3 * 3_600) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let input = file.processingFormat
        guard Double(file.length) / input.sampleRate <= maxSeconds else { throw LoadError.tooLong }
        guard let converter = AVAudioConverter(from: input, to: .speech16kMono),
              let output = AVAudioPCMBuffer(pcmFormat: .speech16kMono, frameCapacity: AVAudioFrameCount(AudioChunk.sampleRate))
        else { throw AudioError.unsupportedFormat }
        let block = AVAudioFrameCount(input.sampleRate)   // a second at a time
        var samples: [Float] = []
        samples.reserveCapacity(Int(Double(file.length) / input.sampleRate * AudioChunk.sampleRate) + 1_024)
        var readError: Error?
        // Fed from the file until it ends, then told so: the converter's last samples come out too.
        while true {
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
                guard file.framePosition < file.length,
                      let buffer = AVAudioPCMBuffer(pcmFormat: input, frameCapacity: block) else {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                do { try file.read(into: buffer, frameCount: block) } catch {
                    readError = error
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                inputStatus.pointee = .haveData
                return buffer
            }
            if let readError { throw readError }
            if let conversionError { throw AudioError.engineFailed(conversionError.localizedDescription) }
            samples += output.floatSamples
            if status == .endOfStream || status == .error { break }
        }
        return samples
    }
}
