import SwiftUI

/// The live preview as a news ticker inside the notch. The line starts just past the right edge
/// and glides left (frame by frame, see `TickerMotion`) at an even, dampened speed, so every
/// word slides in from the right; new words are appended off-screen and follow. Older words
/// scroll out past a faded left edge. Clipped to its frame, so it never widens the capsule.
struct PreviewTicker: View {
    let text: String
    /// Both edges fade to black over this width: words emerge on the right and dissolve on the left.
    static let fadeWidth: CGFloat = 24
    /// Where the newest word comes to rest when speech pauses: just clear of the right fade.
    static let lead: CGFloat = 28

    @State private var textWidth: CGFloat = 0
    @State private var clock = Clock()

    /// How far the line should have travelled left so its end sits `lead` inside the right edge.
    static func scrollTarget(text: CGFloat) -> CGFloat {
        text > 0 ? text + lead : 0
    }

    /// Where the line's start is drawn: at the right edge before it has moved.
    static func textX(container: CGFloat, scrolled: CGFloat) -> CGFloat {
        container - scrolled
    }

    var body: some View {
        GeometryReader { geometry in
            let target = Self.scrollTarget(text: textWidth)
            TimelineView(.animation(paused: clock.motion.isSettled(at: target))) { timeline in
                let scrolled = clock.advance(to: timeline.date, toward: target)
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AuroraTheme.textPrimary.opacity(0.85))
                    .lineLimit(1)
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
                    // Fractional positions on purpose: snapping to pixels makes slow motion stutter.
                    .offset(x: Self.textX(container: geometry.size.width, scrolled: scrolled))
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
            }
        }
        .clipped()
        .mask {
            GeometryReader { geometry in
                LinearGradient(stops: Self.fadeStops(width: geometry.size.width),
                               startPoint: .leading, endPoint: .trailing)
            }
        }
    }

    /// Transparent at both edges, opaque in between, with `fadeWidth` ramps.
    static func fadeStops(width: CGFloat) -> [Gradient.Stop] {
        let ramp = width > 0 ? min(0.5, fadeWidth / width) : 0
        return [.init(color: .clear, location: 0), .init(color: .black, location: ramp),
                .init(color: .black, location: 1 - ramp), .init(color: .clear, location: 1)]
    }

    /// Steps the motion with the real frame time. A reference type so the timeline can advance
    /// it while rendering without invalidating the view.
    final class Clock {
        var motion = TickerMotion()
        private var last: Date?

        func advance(to now: Date, toward target: CGFloat) -> CGFloat {
            // A long gap (paused while settled) restarts the clock instead of jumping.
            let dt = last.map { min(now.timeIntervalSince($0), 1.0 / 30) } ?? 0
            last = now
            motion.step(toward: target, dt: CGFloat(dt))
            return motion.position
        }
    }
}
