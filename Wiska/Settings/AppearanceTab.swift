import Core
import HUD
import SwiftUI

struct AppearanceTab: View {
    let model: AppModel

    var body: some View {
        Form {
            Section("Highlight colour") {
                HStack { Spacer(); HUDPreview(highlight: model.settings.highlight); Spacer() }
                    .padding(.vertical, 8)
                HStack(spacing: 12) {
                    ForEach(Highlight.allCases, id: \.self) { preset in
                        Button {
                            model.settings.highlight = preset
                            model.applyHighlight()
                        } label: {
                            VStack(spacing: 4) {
                                Circle().fill(AuroraTheme.gradient(preset)).frame(width: 28, height: 28)
                                    .overlay(Circle()
                                        .stroke(Color.primary, lineWidth: preset == model.settings.highlight ? 2 : 0)
                                        .padding(-3))
                                Text(preset.displayName).font(.caption2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
                Text("Colours the notch capsule, the waveform and Wiska's accents.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 360, idealHeight: 560, maxHeight: .infinity)
    }
}
