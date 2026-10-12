import CoreGraphics
import Foundation

/// One smoothed 0…1 "how much voice" value for animations (the orb, Clippy), stepped every frame
/// from the same `AudioLevel.level` the waveform reads — no second microphone.
///
/// Uses the waveform's noise gate and compressive curve (`WaveformMotion.loudness`), so quiet
/// speech is already clearly visible and loud speech saturates gently at 1; then rises fast and
/// falls slowly, so frame-to-frame noise doesn't jitter.
struct VoiceEnergy {
    static let attack: Double = 0.08
    static let release: Double = 0.3

    private(set) var value: CGFloat = 0
    private var gateIsOpen = false

    var isResting: Bool { value == 0 }

    mutating func step(level: Float, dt: Double) {
        guard dt > 0 else { return }
        gateIsOpen = level >= (gateIsOpen ? WaveformMotion.gateClose : WaveformMotion.gateOpen)
        let target = gateIsOpen ? WaveformMotion.loudness(level) : 0
        let tau = target > value ? Self.attack : Self.release
        value += (target - value) * CGFloat(1 - exp(-dt / tau))
        if target == 0 && value < 0.003 { value = 0 }
        value = min(1, value)
    }

    /// Steps with the real frame time; a reference type so a timeline can advance it while rendering.
    final class Clock {
        private(set) var energy = VoiceEnergy()
        private var last: Date?

        func advance(to now: Date, level: Float) -> CGFloat {
            let dt = last.map { min(now.timeIntervalSince($0), 1.0 / 20) } ?? 0
            last = now
            energy.step(level: level, dt: dt)
            return energy.value
        }
    }
}
