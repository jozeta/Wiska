import CoreGraphics
import Testing
@testable import HUD

struct WaveformViewTests {
    @Test func silenceAndRoomNoiseAreFlat() {
        #expect(WaveformView.barHeight(level: 0) == WaveformView.minBar)
        #expect(WaveformView.barHeight(level: 0.15) == WaveformView.minBar)
    }

    @Test func loudSpeechFillsTheWholeHeight() {
        #expect(WaveformView.barHeight(level: 0.8) == WaveformView.maxBar)
        #expect(WaveformView.barHeight(level: 1) == WaveformView.maxBar)
    }

    /// Ordinary speech (≈ 0.4–0.7) spans most of the range, so the bars look wavy.
    @Test func speechUsesMostOfTheRange() {
        let quiet = WaveformView.barHeight(level: 0.4)
        let loud = WaveformView.barHeight(level: 0.7)
        #expect(loud - quiet > 0.5 * (WaveformView.maxBar - WaveformView.minBar), "\(quiet)…\(loud)")
        #expect(WaveformView.maxBar == 28)
    }
}
