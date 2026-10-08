import SwiftUI

/// Bars for the most recent loudness samples; newest on the right.
struct WaveformView: View {
    static let barCount = 24
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                Capsule()
                    .fill(.primary)
                    .frame(width: 3, height: 4 + CGFloat(level(at: index)) * 24)
            }
        }
        .frame(height: 28)
        .animation(.easeOut(duration: 0.08), value: levels)
    }

    private func level(at index: Int) -> Float {
        let offset = Self.barCount - levels.count
        return index >= offset ? levels[index - offset] : 0
    }
}
