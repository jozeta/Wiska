/// A slice of microphone audio: 16 kHz, mono, Float32 samples in [-1, 1].
public struct AudioChunk: Sendable, Equatable {
    public static let sampleRate: Double = 16_000
    public let samples: [Float]

    public init(samples: [Float]) {
        self.samples = samples
    }
}
