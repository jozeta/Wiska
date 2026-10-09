/// One analysis frame of the microphone (every 16 ms while recording).
public struct AudioLevel: Sendable, Equatable {
    /// Loudness 0…1 on a decibel scale (−50 dBFS → 0, 0 dBFS → 1).
    public var level: Float
    /// Energy per waveform bar in dB, low → high pitch, tilted so speech lights all of them.
    public var bands: [Float]

    public init(level: Float, bands: [Float] = []) {
        self.level = level
        self.bands = bands
    }

    public static let silent = AudioLevel(level: 0)
}
