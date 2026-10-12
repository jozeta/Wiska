import Core
import SwiftUI

@MainActor @Observable
final class ExpandedNotchModel {
    var content: HUDContent = .hidden
    var highlight: Highlight = .aurora
    var centerWidth: CGFloat = ExpandedNotchLayout.gapWithoutNotch
    var height: CGFloat = ExpandedNotchLayout.fallbackHeight
    var hasNotch = false
    /// 0 = folded into the notch, 1 = both sides fully out.
    var reveal: CGFloat = 0
}

/// The state on the left of the notch, the waveform on the right. No live text: the bar is
/// only as tall as the notch, and the words still go through as usual.
struct ExpandedNotchView: View {
    let model: ExpandedNotchModel

    var body: some View {
        let wing = ExpandedNotchLayout.wing
        let radius = min(12, model.height / 3)
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)
        HStack(spacing: 0) {
            state
                .padding(.leading, radius).padding(.trailing, 10)
                .frame(width: wing, alignment: .trailing)
            Color.clear.frame(width: model.centerWidth)
            waveform
                .padding(.leading, 10).padding(.trailing, radius + 2)
                .frame(width: wing)
        }
        .frame(height: model.height)
        .opacity(model.reveal)
        .background {
            shape.fill(Color.black)
                .frame(width: model.centerWidth + 2 * wing * model.reveal)
                .opacity(model.hasNotch ? 1 : model.reveal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(AuroraTheme.textPrimary)
        .lineLimit(1)
    }

    @ViewBuilder private var state: some View {
        switch model.content {
        case .hidden:
            EmptyView()
        case .listening(_, let badge, _, let handsFree, let isCommand):
            HStack(spacing: 6) {
                ExpandedNotchView.badge(badge, handsFree: handsFree, highlight: model.highlight)
                Text(isCommand ? "Command" : "Listening").minimumScaleFactor(0.8)
            }
        case .working(let text, _):
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini).tint(AuroraTheme.start(model.highlight))
                Text(text).minimumScaleFactor(0.75)
            }
        case .message(let text):
            Text(text).minimumScaleFactor(0.7)
        case .error(let text):
            Text(text).minimumScaleFactor(0.7).foregroundStyle(AuroraTheme.danger)
        }
    }

    /// One waveform for the whole dictation, so it settles flat when speech stops instead of vanishing.
    @ViewBuilder private var waveform: some View {
        switch model.content {
        case .hidden, .message, .error:
            Color.clear
        case .listening(let audio, _, _, _, _):
            WaveformView(audio: audio, highlight: model.highlight,
                         scale: ExpandedNotchLayout.waveformScale(height: model.height))
        case .working:
            WaveformView(audio: .silent, highlight: model.highlight,
                         scale: ExpandedNotchLayout.waveformScale(height: model.height))
                .opacity(0.5)
        }
    }

    static func badge(_ text: String, handsFree: Bool, highlight: Highlight) -> some View {
        HStack(spacing: 3) {
            Text(text)
            if handsFree { Image(systemName: "lock.fill").font(.system(size: 7, weight: .bold)) }
        }
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .padding(.horizontal, 4).padding(.vertical, 1.5)
        .foregroundStyle(AuroraTheme.start(highlight))
        .background(AuroraTheme.start(highlight).opacity(0.13), in: RoundedRectangle(cornerRadius: 4))
    }
}

/// The Expanded Notch with a made-up voice, for Settings ▸ Appearance. Never touches the microphone.
public struct ExpandedNotchPreview: View {
    let highlight: Highlight

    public init(highlight: Highlight) { self.highlight = highlight }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { context in
            ExpandedNotchView(model: sample(at: context.date.timeIntervalSinceReferenceDate))
        }
        .frame(width: 2 * ExpandedNotchLayout.wing + 120, height: 32)
    }

    /// A throwaway model per frame: the preview owns no state that rendering would have to change.
    private func sample(at t: Double) -> ExpandedNotchModel {
        let model = ExpandedNotchModel()
        model.highlight = highlight
        model.centerWidth = 120
        model.height = 32
        model.hasNotch = true
        model.reveal = 1
        model.content = .listening(audio: SampleVoice.level(at: t), badge: "AUTO", preview: "", handsFree: false)
        return model
    }
}

/// A made-up voice for previews: loudness and bands that wander like speech.
enum SampleVoice {
    static func level(at t: Double) -> AudioLevel {
        AudioLevel(level: Float(0.35 + 0.15 * sin(t * 2.3)),
                   bands: (0..<WaveformView.barCount).map { i in
                       Float(-22 - Double(i) * 0.8 + 9 * sin(t * 5 + Double(i) * 0.7))
                   })
    }
}
