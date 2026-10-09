import Core
import CoreGraphics
import Testing
@testable import HUD

/// The acceptance table: silence flat, quiet speech clearly active, normal speech tall and
/// varied, loud speech only somewhat taller, quick onset, visible dips in pauses.
struct WaveformMotionTests {
    /// A speech-like spectrum: strong low-mid bars, weaker highs, with some unevenness.
    static let voice: [Float] = (0..<WaveformMotion.barCount).map { i in
        -20 - Float(i) * 0.75 - (i % 3 == 0 ? 0 : 7)
    }

    private func frame(_ level: Float, bands: [Float] = voice) -> AudioLevel {
        AudioLevel(level: level, bands: bands)
    }

    private func run(_ motion: inout WaveformMotion, _ audio: AudioLevel, seconds: Double) {
        for _ in 0..<max(1, Int(seconds * 120)) { motion.step(audio, dt: 1.0 / 120) }
    }

    private func bars(_ motion: WaveformMotion) -> [CGFloat] {
        (0..<WaveformView.barCount).map { motion.bar($0) }
    }

    private var range: CGFloat { WaveformView.maxBar - WaveformView.minBar }
    private func mean(_ values: [CGFloat]) -> CGFloat { values.reduce(0, +) / CGFloat(values.count) }

    @Test func silenceAndBackgroundNoiseStayFlat() {
        var motion = WaveformMotion()
        run(&motion, frame(0.0), seconds: 0.5)
        #expect(bars(motion).allSatisfy { $0 == WaveformView.minBar })
        run(&motion, frame(WaveformMotion.gateClose - 0.01), seconds: 0.5)   // room noise
        #expect(bars(motion).allSatisfy { $0 == WaveformView.minBar })
    }

    @Test func veryQuietSpeechIsClearlyActive() {
        var motion = WaveformMotion()
        run(&motion, frame(WaveformMotion.gateOpen + 0.02), seconds: 0.3)    // ≈ −42 dBFS
        #expect(mean(bars(motion)) > WaveformView.minBar + 0.3 * range, "\(bars(motion))")
    }

    @Test func normalSpeechIsTallAndVaried() {
        var motion = WaveformMotion()
        run(&motion, frame(0.4), seconds: 0.3)                                // ≈ −30 dBFS
        let heights = bars(motion)
        #expect(heights.max()! > WaveformView.minBar + 0.8 * range, "\(heights)")
        #expect(heights.max()! - heights.min()! > 8, "\(heights)")
    }

    /// Non-linear: quiet → normal is a big step, normal → loud a smaller one.
    @Test func loudSpeechIsOnlySomewhatTaller() {
        func level(_ value: Float) -> CGFloat {
            var motion = WaveformMotion()
            run(&motion, frame(value), seconds: 0.3)
            return mean(bars(motion))
        }
        let quiet = level(WaveformMotion.gateOpen + 0.02), normal = level(0.4), loud = level(0.8)
        #expect(loud > normal)
        #expect(normal - quiet > loud - normal)
    }

    @Test func onsetIsImmediateAndPausesDip() {
        var motion = WaveformMotion()
        run(&motion, frame(0.4), seconds: 0.03)
        let onset = mean(bars(motion))
        #expect(onset > WaveformView.minBar + 0.4 * range, "onset \(onset)")
        run(&motion, frame(0.4), seconds: 0.3)
        run(&motion, frame(0.02), seconds: 0.1)                                // a pause
        #expect(mean(bars(motion)) < WaveformView.minBar + 0.25 * range)
    }

    /// Detail comes from the audio: the loudest band draws the tallest bar.
    @Test func barsFollowTheirBands() {
        var bands = [Float](repeating: -50, count: WaveformMotion.barCount)
        bands[13] = -15
        var motion = WaveformMotion()
        run(&motion, frame(0.4, bands: bands), seconds: 0.3)
        let heights = bars(motion)
        #expect(heights.indices.max { heights[$0] < heights[$1] } == 13)
    }

    /// No invented motion: a steady sound holds steady bars.
    @Test func aSteadySoundHoldsSteadyBars() {
        var motion = WaveformMotion()
        run(&motion, frame(0.4), seconds: 0.5)
        let before = bars(motion)
        run(&motion, frame(0.4), seconds: 0.2)
        #expect(zip(before, bars(motion)).allSatisfy { abs($0 - $1) < 0.01 })
    }
}
