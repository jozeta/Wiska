import Core
import SwiftUI

/// Live bars for the microphone level (the newest of `levels`), animated every frame by
/// `WaveformMotion`: flat in silence, a rippling wave while sound comes in; coloured along the highlight.
struct WaveformView: View {
    static let barCount = 20
    static let minBar: CGFloat = 3
    static let maxBar: CGFloat = 28
    let levels: [Float]
    let highlight: Highlight
    @State private var clock = Clock()

    var body: some View {
        let level = levels.last ?? 0
        TimelineView(.animation(paused: level == 0 && clock.motion.envelope == 0)) { timeline in
            let time = clock.advance(to: timeline.date, level: level)
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<Self.barCount, id: \.self) { index in
                    Capsule()
                        .fill(color(at: index))
                        .frame(width: 3, height: clock.motion.bar(index, time: time))
                }
            }
            .frame(height: Self.maxBar)
        }
    }

    private func color(at index: Int) -> Color {
        AuroraTheme.color(highlight, at: Double(index) / Double(Self.barCount - 1))
    }

    /// Steps the motion with the real frame time; a reference type so the timeline can advance
    /// it while rendering without invalidating the view.
    final class Clock {
        var motion = WaveformMotion()
        private var last: Date?

        func advance(to now: Date, level: Float) -> Double {
            let dt = last.map { min(now.timeIntervalSince($0), 1.0 / 30) } ?? 0
            last = now
            motion.step(level: level, dt: dt)
            return now.timeIntervalSinceReferenceDate
        }
    }
}
