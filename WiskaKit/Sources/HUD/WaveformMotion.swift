import CoreGraphics
import Foundation

/// The live waveform's motion, stepped every frame. An envelope follower (fast attack, slower
/// release) turns the microphone level into loudness; each bar is that loudness shaped by a bell
/// (tallest in the middle) and a ripple that moves over time, so speech looks like a living wave
/// and silence is flat.
struct WaveformMotion {
    /// Levels at or below this (room noise) count as silence.
    static let noiseFloor: Float = 0.22
    /// Levels at or above this (loud speech) are full loudness.
    static let fullScale: Float = 0.65
    /// > 1: quiet sounds stay small and loud ones jump, for a dramatic contrast.
    static let curve: Float = 1.6
    static let attack: Double = 0.02
    static let release: Double = 0.12

    private(set) var envelope: CGFloat = 0

    static func loudness(_ level: Float) -> CGFloat {
        let span = max(0, min(1, (level - noiseFloor) / (fullScale - noiseFloor)))
        return CGFloat(pow(span, curve))
    }

    mutating func step(level: Float, dt: Double) {
        guard dt > 0 else { return }
        let target = Self.loudness(level)
        let tau = target > envelope ? Self.attack : Self.release
        envelope += (target - envelope) * CGFloat(1 - exp(-dt / tau))
        if envelope < 0.001 { envelope = 0 }
    }

    /// Bar `index`'s height at `time` (seconds, any steady clock).
    func bar(_ index: Int, time: Double) -> CGFloat {
        let minBar = WaveformView.minBar, maxBar = WaveformView.maxBar
        guard envelope > 0 else { return minBar }
        let count = Double(WaveformView.barCount)
        let i = Double(index)
        let bell = 0.45 + 0.55 * sin(Double.pi * (i + 0.5) / count)
        let ripple = 0.6 + 0.4 * sin(time * 6.3 + i * 0.8 + sin(time * 2.1 + i * 0.35) * 1.5)
        let value = min(1, envelope * CGFloat(bell * ripple))
        return minBar + value * (maxBar - minBar)
    }
}
