import SwiftUI

/// The live preview as a ticker inside the notch. The text is laid out once at its natural
/// width; when it overflows, the whole line glides left (frame by frame, see `TickerMotion`)
/// at an even, dampened speed so the newest words come into view. Older words scroll out past
/// a faded left edge. Clipped to its frame, so it never widens the capsule.
struct PreviewTicker: View {
    let text: String
    /// Room kept free at the right edge for the next words.
    static let lead: CGFloat = 24

    @State private var textWidth: CGFloat = 0
    @State private var clock = Clock()
    @Environment(\.displayScale) private var displayScale

    /// How far the line should be scrolled left so its end sits `lead` from the right edge.
    static func scrollTarget(container: CGFloat, text: CGFloat) -> CGFloat {
        max(0, text - (container - lead))
    }

    var body: some View {
        GeometryReader { geometry in
            let target = Self.scrollTarget(container: geometry.size.width, text: textWidth)
            TimelineView(.animation(paused: clock.motion.isSettled(at: target))) { timeline in
                let scrolled = clock.advance(to: timeline.date, toward: target)
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AuroraTheme.textPrimary.opacity(0.85))
                    .lineLimit(1)
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
                    // Whole pixels: text drawn at fractional offsets shimmers while it moves.
                    .offset(x: -(scrolled * displayScale).rounded() / displayScale)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
            }
        }
        .clipped()
        .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.1)],
                           startPoint: .leading, endPoint: .trailing)
        }
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
