import Core
import CoreGraphics
import Foundation

/// The waveform's visual mapping, stepped every frame from real microphone analysis
/// (`AudioLevel`: loudness + pitch bands). Nothing moves that the audio didn't move.
///
/// - A noise gate (with hysteresis) keeps silence and room noise flat.
/// - Loudness goes through a compressive curve (exponent < 1): quiet speech already looks
///   lively, loud speech only somewhat more. Once speech is detected, a floor keeps it visible.
/// - Each bar's share comes from its own band relative to the loudest band in the frame,
///   so the shape follows syllables, consonants and pitch.
/// - Each bar rises fast (attack) and falls a little slower (release).
struct WaveformMotion {
    /// One bar per analyzer band (`SpectrumAnalyzer.bandCount`).
    static let barCount = 32
    /// Loudness (0…1 = −50…0 dBFS) at which the gate opens: ≈ −43 dBFS, very quiet speech.
    static let gateOpen: Float = 0.14
    /// …and below which it closes again: ≈ −45 dBFS, room noise.
    static let gateClose: Float = 0.10
    /// Loudness that reaches the full visual height: ≈ −18 dBFS, loud speech.
    static let ceiling: Float = 0.64
    /// < 1 amplifies quiet input and compresses loud input.
    static let exponent: Float = 0.45
    /// Minimum visual loudness once speech is detected.
    static let speechFloor: CGFloat = 0.3
    /// Bands this many dB below the frame's loudest band draw no extra height.
    static let bandRange: Float = 30
    /// Share of a bar's height that every bar gets regardless of its band.
    static let baseShare: CGFloat = 0.4
    static let attack: Double = 0.015
    static let release: Double = 0.09

    /// Rise and fall times; the orb uses slower ones than the waveform's bars.
    var attackTime = WaveformMotion.attack
    var releaseTime = WaveformMotion.release
    private var gateIsOpen = false
    private var heights = [CGFloat](repeating: 0, count: WaveformMotion.barCount)

    var isFlat: Bool { heights.allSatisfy { $0 == 0 } }

    static func loudness(_ level: Float) -> CGFloat {
        let span = max(0, min(1, (level - gateClose) / (ceiling - gateClose)))
        return speechFloor + (1 - speechFloor) * CGFloat(pow(span, exponent))
    }

    mutating func step(_ audio: AudioLevel, dt: Double) {
        guard dt > 0 else { return }
        gateIsOpen = audio.level >= (gateIsOpen ? Self.gateClose : Self.gateOpen)
        let targets = gateIsOpen ? Self.targets(audio) : [CGFloat](repeating: 0, count: heights.count)
        for index in heights.indices {
            let target = targets[index]
            let tau = target > heights[index] ? attackTime : releaseTime
            heights[index] += (target - heights[index]) * CGFloat(1 - exp(-dt / tau))
            if heights[index] < 0.002 && target == 0 { heights[index] = 0 }
        }
    }

    /// Each bar's target, 0…1.
    static func targets(_ audio: AudioLevel) -> [CGFloat] {
        let loud = loudness(audio.level)
        let count = Self.barCount
        guard audio.bands.count == count, let peak = audio.bands.max() else {
            return [CGFloat](repeating: loud, count: count)
        }
        return audio.bands.map { band in
            let share = max(0, min(1, 1 + (band - peak) / bandRange))
            return loud * (baseShare + (1 - baseShare) * CGFloat(pow(share, 0.7)))
        }
    }

    /// Each band's smoothed share, 0…1.
    var shares: [CGFloat] { heights.map { min(1, $0) } }

    func bar(_ index: Int) -> CGFloat {
        WaveformView.minBar + min(1, heights[index]) * (WaveformView.maxBar - WaveformView.minBar)
    }
}
