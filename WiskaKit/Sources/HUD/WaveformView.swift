import Core
import SwiftUI

/// Live bars driven by real microphone analysis (`audio`: loudness + one pitch band per bar),
/// stepped every frame by `WaveformMotion`; coloured along the highlight. Fills the width it is
/// given: each thin bar sits centred in an equal slot.
struct WaveformView: View {
    static let barCount = WaveformMotion.barCount
    static let minBar: CGFloat = 3
    static let maxBar: CGFloat = 28
    static let barWidth: CGFloat = 2
    let audio: AudioLevel
    let highlight: Highlight
    @State private var clock = Clock()

    var body: some View {
        TimelineView(.animation(paused: audio.level == 0 && clock.motion.isFlat)) { timeline in
            let _ = clock.advance(to: timeline.date, audio: audio)
            HStack(alignment: .center, spacing: 0) {
                ForEach(0..<Self.barCount, id: \.self) { index in
                    Capsule()
                        .fill(color(at: index))
                        .frame(width: Self.barWidth, height: clock.motion.bar(index))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
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

        func advance(to now: Date, audio: AudioLevel) {
            let dt = last.map { min(now.timeIntervalSince($0), 1.0 / 30) } ?? 0
            last = now
            motion.step(audio, dt: dt)
        }
    }
}
