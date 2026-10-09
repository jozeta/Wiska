import SwiftUI

/// The live preview as a ticker inside the notch: one line anchored to the right edge, so new
/// words slide in from the right and older ones scroll out past a faded left edge.
/// The text is laid out at its natural width and clipped, so it never widens the capsule.
struct PreviewTicker: View {
    let text: String

    var body: some View {
        Color.clear
            .overlay(alignment: .trailing) {
                Text(text)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(AuroraTheme.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .animation(.easeOut(duration: 0.25), value: text)
            }
            .clipped()
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12)],
                               startPoint: .leading, endPoint: .trailing)
            }
    }
}
