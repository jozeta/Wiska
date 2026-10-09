import Core
import SwiftUI

/// The capsule as it looks while listening, with a moving sample waveform — for Settings ▸ Appearance.
public struct HUDPreview: View {
    let highlight: Highlight

    public init(highlight: Highlight) { self.highlight = highlight }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // A made-up voice for the preview: loudness and bands that wander like speech.
            let audio = AudioLevel(
                level: Float(0.35 + 0.15 * sin(t * 2.3)),
                bands: (0..<WaveformView.barCount).map { i in
                    Float(-22 - Double(i) * 0.8 + 9 * sin(t * 5 + Double(i) * 0.7))
                })
            HStack(spacing: 10) {
                Text("AUTO")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .foregroundStyle(AuroraTheme.start(highlight))
                    .background(AuroraTheme.start(highlight).opacity(0.13), in: RoundedRectangle(cornerRadius: 4))
                WaveformView(audio: audio, highlight: highlight)
            }
            .frame(width: NotchLayout.fallbackWidth, height: HUDView.contentHeight)
            .background(Color.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18))
        }
    }
}
