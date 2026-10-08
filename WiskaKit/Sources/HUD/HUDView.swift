import SwiftUI

struct HUDView: View {
    let model: HUDModel

    var body: some View {
        Group {
            switch model.content {
            case .hidden:
                EmptyView()
            case .listening(let levels, let badge):
                HStack(spacing: 10) {
                    Text(badge)
                        .font(.caption2.weight(.bold).monospaced())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    WaveformView(levels: levels)
                }
            case .working(let text):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(text)
                }
            case .message(let text):
                Text(text)
            }
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
