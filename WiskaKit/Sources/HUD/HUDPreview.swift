import Core
import SwiftUI

/// The capsule as it looks while listening, with a moving sample waveform — for Settings ▸ Appearance.
public struct HUDPreview: View {
    let highlight: Highlight

    public init(highlight: Highlight) { self.highlight = highlight }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let levels = (0..<WaveformView.barCount).map { i in
                Float(0.25 + 0.75 * abs(sin(t * 3 + Double(i) * 0.45)))
            }
            HStack(spacing: 10) {
                Text("AUTO")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .foregroundStyle(AuroraTheme.start(highlight))
                    .background(AuroraTheme.start(highlight).opacity(0.13), in: RoundedRectangle(cornerRadius: 4))
                WaveformView(levels: levels, highlight: highlight)
            }
            .frame(width: NotchLayout.fallbackWidth, height: HUDView.contentHeight)
            .background(Color.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18))
        }
    }
}
