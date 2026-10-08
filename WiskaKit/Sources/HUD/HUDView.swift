import SwiftUI

struct HUDView: View {
    let model: HUDModel

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.insetTop)       // the notch itself
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black, in: UnevenRoundedRectangle(
            topLeadingRadius: model.hasNotch ? 0 : 18, bottomLeadingRadius: 18,
            bottomTrailingRadius: 18, topTrailingRadius: model.hasNotch ? 0 : 18))
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(AuroraTheme.textPrimary)
    }

    @ViewBuilder private var content: some View {
        switch model.content {
        case .hidden:
            EmptyView()
        case .listening(let levels, let badge):
            HStack(spacing: 10) {
                Text(badge)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .foregroundStyle(AuroraTheme.teal)
                    .background(AuroraTheme.teal.opacity(0.13), in: RoundedRectangle(cornerRadius: 4))
                WaveformView(levels: levels)
            }
        case .working(let text):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(AuroraTheme.teal)
                Text(text)
            }
        case .message(let text):
            Text(text).foregroundStyle(model.isError ? AuroraTheme.danger : AuroraTheme.textPrimary)
        }
    }
}
