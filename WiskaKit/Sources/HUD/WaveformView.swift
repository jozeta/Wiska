import Core
import SwiftUI

/// Bars for the most recent loudness samples; newest on the right, coloured along the highlight.
struct WaveformView: View {
    static let barCount = 20
    let levels: [Float]
    let highlight: Highlight

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                Capsule()
                    .fill(color(at: index))
                    .frame(width: 3, height: 4 + CGFloat(level(at: index)) * 20)
            }
        }
        .frame(height: 24)
        .animation(.easeOut(duration: 0.08), value: levels)
    }

    private func level(at index: Int) -> Float {
        let offset = Self.barCount - levels.count
        return index >= offset ? levels[index - offset] : 0
    }

    private func color(at index: Int) -> Color {
        let t = Double(index) / Double(Self.barCount - 1)
        func channel(_ shift: UInt32) -> Double {
            let a = Double((highlight.start >> shift) & 0xFF), b = Double((highlight.end >> shift) & 0xFF)
            return (a + (b - a) * t) / 255
        }
        return Color(.sRGB, red: channel(16), green: channel(8), blue: channel(0))
    }
}
