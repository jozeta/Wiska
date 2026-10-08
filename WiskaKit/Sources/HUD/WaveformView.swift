import SwiftUI

/// Bars for the most recent loudness samples; newest on the right, coloured teal → violet.
struct WaveformView: View {
    static let barCount = 20
    let levels: [Float]

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
        return Color(red: (0x3E + (0x8B - 0x3E) * t) / 255,
                     green: (0xE6 + (0x6C - 0xE6) * t) / 255,
                     blue: (0xC1 + (0xFF - 0xC1) * t) / 255)
    }
}
