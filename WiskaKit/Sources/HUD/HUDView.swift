import Core
import SwiftUI

struct HUDView: View {
    let model: HUDModel
    static let contentHeight: CGFloat = 44

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 18,
                                           bottomTrailingRadius: 18, topTrailingRadius: 0)
        let visible = HUDReveal.visibleHeight(insetTop: model.insetTop, contentHeight: Self.contentHeight,
                                              reveal: model.reveal)
        VStack(spacing: 0) {
            Color.clear.frame(height: model.insetTop)       // the notch itself
            content
                .lineLimit(1).truncationMode(.tail)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .frame(height: Self.contentHeight)
                .opacity(model.reveal)
                .offset(y: HUDReveal.contentOffset(reveal: model.reveal))
        }
        .background(alignment: .top) { shape.fill(Color.black).frame(height: visible) }
        .mask(alignment: .top) { shape.frame(height: visible) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                    .foregroundStyle(AuroraTheme.start(model.highlight))
                    .background(AuroraTheme.start(model.highlight).opacity(0.13), in: RoundedRectangle(cornerRadius: 4))
                WaveformView(levels: levels, highlight: model.highlight)
            }
        case .working(let text):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(AuroraTheme.start(model.highlight))
                Text(text)
            }
        case .message(let text):
            Text(text)
        case .error(let text):
            Text(text).foregroundStyle(AuroraTheme.danger)
        }
    }
}
