import SwiftUI

struct HUDView: View {
    let model: HUDModel

    var body: some View {
        Group {
            switch model.content {
            case .hidden:
                EmptyView()
            case .listening(let levels):
                WaveformView(levels: levels)
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
