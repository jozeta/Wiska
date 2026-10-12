import Core
import CoreGraphics
import Testing
@testable import HUD

struct VoiceEnergyTests {
    private func run(_ energy: inout VoiceEnergy, level: Float, seconds: Double) {
        for _ in 0..<Int(seconds * 60) { energy.step(level: level, dt: 1.0 / 60) }
    }

    @Test func silenceAndRoomNoiseStayAtRest() {
        var energy = VoiceEnergy()
        run(&energy, level: 0, seconds: 1)
        #expect(energy.value == 0)
        run(&energy, level: 0.09, seconds: 2)   // ≈ −45 dBFS room noise
        #expect(energy.value == 0)
        #expect(energy.isResting)
    }

    @Test func quietSpeechIsClearlyVisible() {
        var energy = VoiceEnergy()
        run(&energy, level: 0.16, seconds: 0.5)   // ≈ −42 dBFS
        #expect(energy.value > 0.3)
    }

    @Test func loudSpeechIsStrongerButCapped() {
        var quiet = VoiceEnergy(), loud = VoiceEnergy()
        run(&quiet, level: 0.2, seconds: 1)
        run(&loud, level: 1, seconds: 1)
        #expect(loud.value > quiet.value)
        #expect(loud.value <= 1)
    }

    @Test func noisyInputDoesNotJitter() {
        var energy = VoiceEnergy()
        run(&energy, level: 0.4, seconds: 1)
        var largestStep: CGFloat = 0
        for frame in 0..<120 {
            let before = energy.value
            energy.step(level: frame.isMultiple(of: 2) ? 0.3 : 0.5, dt: 1.0 / 60)
            largestStep = max(largestStep, abs(energy.value - before))
        }
        #expect(largestStep < 0.05)
    }

    @Test func fallsBackToRestWhenSpeechStops() {
        var energy = VoiceEnergy()
        run(&energy, level: 0.5, seconds: 1)
        run(&energy, level: 0, seconds: 3)
        #expect(energy.value == 0)
    }
}
