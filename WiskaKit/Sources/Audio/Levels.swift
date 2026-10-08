import Foundation

/// Loudness helpers for the HUD waveform.
public enum Levels {
    static let floorDecibels: Float = -50

    public static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return (sumOfSquares / Float(samples.count)).squareRoot()
    }

    /// Maps RMS to 0…1 on a decibel scale: floorDecibels → 0, 0 dBFS → 1.
    public static func normalized(rms: Float) -> Float {
        let decibels = 20 * log10(max(rms, 1e-7))
        return min(max((decibels - floorDecibels) / -floorDecibels, 0), 1)
    }
}
