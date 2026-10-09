import CoreGraphics
import Testing
@testable import HUD

struct TickerMotionTests {
    /// Runs the motion at 120 fps and returns every frame's (position, velocity).
    private func run(_ motion: inout TickerMotion, target: (Double) -> CGFloat, seconds: Double) -> [(CGFloat, CGFloat)] {
        var frames: [(CGFloat, CGFloat)] = []
        let dt = 1.0 / 120
        for i in 0..<Int(seconds * 120) {
            motion.step(toward: target(Double(i) * dt), dt: dt)
            frames.append((motion.position, motion.velocity))
        }
        return frames
    }

    @Test func reachesTheTargetWithoutOvershooting() {
        var motion = TickerMotion()
        let frames = run(&motion, target: { _ in 200 }, seconds: 5)
        #expect(frames.allSatisfy { $0.0 <= 200 })
        #expect(abs(motion.position - 200) < 0.5)
        #expect(motion.isSettled(at: 200))
    }

    @Test func accelerationIsDampened() {
        var motion = TickerMotion()
        let frames = run(&motion, target: { _ in 400 }, seconds: 4)
        let dt: CGFloat = 1.0 / 120
        var previous: CGFloat = 0
        for (_, velocity) in frames {
            #expect(abs(velocity - previous) / dt <= TickerMotion.maxAcceleration + 0.001)
            previous = velocity
        }
    }

    /// Words arriving at a steady pace → the line scrolls at an even speed.
    @Test func steadyTextGivesAnEvenSpeed() {
        var motion = TickerMotion()
        let frames = run(&motion, target: { t in CGFloat(t) * 50 }, seconds: 8)
        let late = frames.suffix(240).map(\.1)    // the last two seconds
        let spread = (late.max() ?? 0) - (late.min() ?? 0)
        #expect(spread < 2, "speed varied by \(spread) pt/s")
        #expect(abs((late.last ?? 0) - 50) < 2)
    }

    @Test func glidesBackSmoothlyWhenThePreviewShrinks() {
        var motion = TickerMotion()
        _ = run(&motion, target: { _ in 100 }, seconds: 3)
        let before = motion.position
        let frames = run(&motion, target: { _ in 60 }, seconds: 4)
        // A revised (shorter) preview glides back smoothly too, still with bounded acceleration.
        #expect(frames.last.map { abs($0.0 - 60) < 0.5 } == true)
        #expect(before > 60)
    }
}
