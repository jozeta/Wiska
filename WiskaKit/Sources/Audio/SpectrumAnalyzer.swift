import Accelerate
import Core

/// Turns 16 kHz microphone samples into `AudioLevel` frames for the waveform: a 32 ms Hann
/// window every 16 ms, its loudness, and its energy in `bandCount` log-spaced pitch bands.
/// Used on the audio thread only (one caller at a time); it keeps the partial window between calls.
public final class SpectrumAnalyzer: @unchecked Sendable {
    public static let windowSize = 512
    public static let hop = 256
    public static let bandCount = 32
    public static let floorDecibels: Float = -100
    static let sampleRate: Float = 16_000
    static let lowHz: Float = 90
    static let highHz: Float = 7_000
    /// Speech energy falls with pitch; add this many dB per octave above 500 Hz (and remove
    /// below) so high and low bars both move.
    static let tiltPerOctave: Float = 3

    private var pending: [Float] = []
    private let dft: vDSP.DiscreteFourierTransform<Float>
    private let window: [Float]
    /// FFT bins summed into each band; consecutive and never shared, so no two bars move as one.
    let bandBins: [Range<Int>]
    private let tilt: [Float]
    private let zeros: [Float]

    public init() {
        let n = Self.windowSize
        dft = try! vDSP.DiscreteFourierTransform(count: n, direction: .forward,
                                                 transformType: .complexComplex, ofType: Float.self)
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)
        zeros = [Float](repeating: 0, count: n)
        let binHz = Self.sampleRate / Float(n)
        var bins: [Range<Int>] = []
        var tilt: [Float] = []
        for k in 0..<Self.bandCount {
            let lowF = Self.lowHz * pow(Self.highHz / Self.lowHz, Float(k) / Float(Self.bandCount))
            let highF = Self.lowHz * pow(Self.highHz / Self.lowHz, Float(k + 1) / Float(Self.bandCount))
            // The lowest bands are narrower than a bin: give each the next unused bin instead.
            let lo = max(bins.last?.upperBound ?? 1, Int((lowF / binHz).rounded()))
            let hi = max(lo + 1, Int((highF / binHz).rounded()))
            bins.append(lo..<min(hi, n / 2))
            tilt.append(Self.tiltPerOctave * log2((lowF * highF).squareRoot() / 500))
        }
        bandBins = bins
        self.tilt = tilt
    }

    public func analyze(_ samples: [Float]) -> [AudioLevel] {
        pending.append(contentsOf: samples)
        var frames: [AudioLevel] = []
        var start = 0
        while pending.count - start >= Self.windowSize {
            frames.append(frame(Array(pending[start..<start + Self.windowSize])))
            start += Self.hop
        }
        pending.removeFirst(start)
        return frames
    }

    private func frame(_ samples: [Float]) -> AudioLevel {
        let level = Levels.normalized(rms: Levels.rms(samples))
        let windowed = vDSP.multiply(samples, window)
        let (real, imaginary) = dft.transform(real: windowed, imaginary: zeros)
        // A full-scale sine peaks at N/4 through a Hann window: that is 0 dB.
        let reference = Float(Self.windowSize * Self.windowSize) / 16
        let bands = bandBins.enumerated().map { index, bins -> Float in
            var power: Float = 0
            for bin in bins { power += real[bin] * real[bin] + imaginary[bin] * imaginary[bin] }
            power /= Float(bins.count)
            let decibels = 10 * log10(power / reference + 1e-12) + tilt[index]
            return max(Self.floorDecibels, decibels)
        }
        return AudioLevel(level: level, bands: bands)
    }
}
