import Core
import SwiftUI

/// Bars for the most recent loudness samples; newest on the right, coloured along the highlight.
struct WaveformView: View {
    static let barCount = 20
    static let minBar: CGFloat = 3
    static let maxBar: CGFloat = 28
    /// Levels at or below this (room noise) draw the smallest bar.
    static let noiseFloor: Float = 0.2
    /// Levels at or above this (loud speech) draw the tallest bar.
    static let fullScale: Float = 0.75
    let levels: [Float]
    let highlight: Highlight

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                Capsule()
                    .fill(color(at: index))
                    .frame(width: 3, height: Self.barHeight(level: level(at: index)))
            }
        }
        .frame(height: Self.maxBar)
        .animation(.easeOut(duration: 0.08), value: levels)
    }

    /// Room noise stays flat; speech is stretched over the full height, and the curve (> 1)
    /// lifts loud moments above ordinary ones so the bars look wavy rather than uniform.
    static func barHeight(level: Float) -> CGFloat {
        let span = max(0, min(1, (level - noiseFloor) / (fullScale - noiseFloor)))
        return minBar + CGFloat(pow(span, 1.3)) * (maxBar - minBar)
    }

    private func level(at index: Int) -> Float {
        let offset = Self.barCount - levels.count
        return index >= offset ? levels[index - offset] : 0
    }

    private func color(at index: Int) -> Color {
        AuroraTheme.color(highlight, at: Double(index) / Double(Self.barCount - 1))
    }
}
