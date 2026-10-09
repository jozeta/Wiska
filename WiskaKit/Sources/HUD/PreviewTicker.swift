import SwiftUI

/// The live preview as a ticker inside the notch. The text is laid out once at its natural
/// width and never re-anchored; when it overflows, the whole line glides left so the newest
/// words stay in view, and older words scroll out past a faded left edge.
/// Clipped to its frame, so it never widens the capsule.
struct PreviewTicker: View {
    let text: String
    @State private var textWidth: CGFloat = 0

    /// How far the line is shifted left so its end is visible.
    static func offset(container: CGFloat, text: CGFloat) -> CGFloat {
        min(0, container - text)
    }

    var body: some View {
        GeometryReader { geometry in
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AuroraTheme.textPrimary.opacity(0.85))
                .lineLimit(1)
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
                .offset(x: Self.offset(container: geometry.size.width, text: textWidth))
                .animation(.smooth(duration: 0.45), value: textWidth)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
        }
        .clipped()
        .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.1)],
                           startPoint: .leading, endPoint: .trailing)
        }
    }
}
