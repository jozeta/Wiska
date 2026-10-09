import CoreGraphics
import Testing
@testable import HUD

struct WaveformMotionTests {
    private func settle(_ motion: inout WaveformMotion, level: Float, seconds: Double) {
        for _ in 0..<Int(seconds * 120) { motion.step(level: level, dt: 1.0 / 120) }
    }

    @Test func silenceIsFlatAtAnyMoment() {
        var motion = WaveformMotion()
        settle(&motion, level: 0.1, seconds: 1)
        for t in [0.0, 0.3, 1.7] {
            for i in 0..<WaveformView.barCount {
                #expect(motion.bar(i, time: t) == WaveformView.minBar)
            }
        }
    }

    @Test func reactsWithinAFewFrames() {
        var motion = WaveformMotion()
        settle(&motion, level: 0.9, seconds: 0.05)
        #expect(motion.envelope > 0.8)
    }

    @Test func fallsBackMoreSlowlyThanItRises() {
        var motion = WaveformMotion()
        settle(&motion, level: 0.9, seconds: 0.5)
        settle(&motion, level: 0, seconds: 0.05)
        #expect(motion.envelope > 0.4)
        settle(&motion, level: 0, seconds: 0.6)
        #expect(motion.envelope < 0.05)
    }

    @Test func loudSpeechReachesFullHeightInTheMiddle() {
        var motion = WaveformMotion()
        settle(&motion, level: 0.9, seconds: 0.5)
        let middle = (0..<40).map { motion.bar(WaveformView.barCount / 2, time: Double($0) * 0.05) }
        #expect(middle.max()! > WaveformView.maxBar - 1)
    }

    @Test func speechIsWavyAcrossBarsAndOverTime() {
        var motion = WaveformMotion()
        settle(&motion, level: 0.6, seconds: 0.5)
        let now = (0..<WaveformView.barCount).map { motion.bar($0, time: 1) }
        #expect(now.max()! - now.min()! > 8, "\(now)")
        let later = (0..<WaveformView.barCount).map { motion.bar($0, time: 1.15) }
        #expect(zip(now, later).contains { abs($0 - $1) > 2 })
        #expect(now.allSatisfy { $0 >= WaveformView.minBar && $0 <= WaveformView.maxBar })
    }
}
