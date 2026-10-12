import Core
import HUD
import Preferences
import SwiftUI

struct AppearanceTab: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section("Dictation appearance") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                    ForEach(DictationTheme.allCases, id: \.self) { theme in
                        ThemeCard(theme: theme, highlight: settings.highlight,
                                  orbColour: settings.orbHighlight ?? settings.highlight,
                                  selected: theme == settings.dictationTheme) {
                            settings.dictationTheme = theme
                            model.applyAppearance()
                        }
                    }
                }
                .padding(.vertical, 4)
                Text("Previews use a made-up voice; the microphone stays off.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            themeOptions(settings)

            Section("Highlight colour") {
                if settings.dictationTheme == .notchDropdown {
                    HStack { Spacer(); HUDPreview(highlight: settings.highlight); Spacer() }
                        .padding(.vertical, 8)
                }
                HighlightSwatches(selection: settings.highlight) {
                    settings.highlight = $0
                    model.applyAppearance()
                }
                Text("Colours the notch, the waveform and Wiska's accents.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private func themeOptions(_ settings: SettingsStore) -> some View {
        switch settings.dictationTheme {
        case .notchDropdown:
            EmptyView()
        case .expandedNotch:
            Section("Expanded Notch") {
                Text("The waveform uses the highlight colour below. This theme shows no live text — your words are still typed as usual.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .orb:
            Section("Magical Orb") {
                HStack {
                    Spacer()
                    OrbPreview(colour: settings.orbHighlight ?? settings.highlight, side: settings.orbSize)
                        .frame(height: SettingsStore.orbSizeRange.upperBound)
                    Spacer()
                }
                LabeledContent("Orb size") {
                    Slider(value: Binding(get: { settings.orbSize },
                                          set: { settings.orbSize = $0.rounded(); model.applyAppearance() }),
                           in: SettingsStore.orbSizeRange, step: 10) {
                        EmptyView()
                    } minimumValueLabel: {
                        Image(systemName: "circle.fill").font(.system(size: 6))
                    } maximumValueLabel: {
                        Image(systemName: "circle.fill").font(.system(size: 14))
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Orb colour")
                    HighlightSwatches(selection: settings.orbHighlight, followsHighlight: settings.highlight) {
                        settings.orbHighlight = $0
                        model.applyAppearance()
                    }
                }
                behaviorPicker("Orb window behavior", selection: settings.orbWindowBehavior) {
                    settings.orbWindowBehavior = $0
                    model.applyAppearance()
                }
                Text("Drag the orb anywhere; it stays where you leave it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .clippy:
            Section("Clippy") {
                behaviorPicker("Clippy window behavior", selection: settings.clippyWindowBehavior) {
                    settings.clippyWindowBehavior = $0
                    model.applyAppearance()
                }
                Text("Drag Clippy anywhere; its bubble follows. The bubble shows your words as you speak when “Show live preview” is on (General).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func behaviorPicker(_ title: String, selection: FloatingWindowBehavior,
                                set: @escaping (FloatingWindowBehavior) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(title, selection: Binding(get: { selection }, set: set)) {
                ForEach(FloatingWindowBehavior.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(selection == .alwaysOnTop
                 ? "Stays above your app windows."
                 : "Lives on the desktop, above the wallpaper and icons; app windows cover it. (macOS has no way to put a window inside the desktop itself.)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// One theme to choose: a live miniature, its name and what it does.
private struct ThemeCard: View {
    let theme: DictationTheme
    let highlight: Highlight
    let orbColour: Highlight
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(colors: [Color(white: 0.32), Color(white: 0.18)],
                                             startPoint: .top, endPoint: .bottom))
                    preview
                }
                .frame(height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                HStack(spacing: 6) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                    Text(theme.displayName).font(.headline)
                }
                Text(theme.summary)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 10)
                .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var preview: some View {
        switch theme {
        case .notchDropdown:
            VStack { HUDPreview(highlight: highlight).scaleEffect(0.8); Spacer() }
        case .expandedNotch:
            VStack { ExpandedNotchPreview(highlight: highlight).scaleEffect(0.68); Spacer() }
        case .orb:
            OrbPreview(colour: orbColour, side: 100)
        case .clippy:
            ClippyPreview(highlight: highlight).scaleEffect(0.62)
        }
    }
}

/// The highlight presets as swatches. With `followsHighlight`, a first swatch means
/// "same as the highlight colour" (nil).
private struct HighlightSwatches: View {
    let selection: Highlight?
    var followsHighlight: Highlight?
    let choose: (Highlight?) -> Void

    init(selection: Highlight?, followsHighlight: Highlight? = nil, choose: @escaping (Highlight?) -> Void) {
        self.selection = selection
        self.followsHighlight = followsHighlight
        self.choose = choose
    }

    init(selection: Highlight, choose: @escaping (Highlight) -> Void) {
        self.selection = selection
        followsHighlight = nil
        self.choose = { $0.map(choose) }
    }

    var body: some View {
        HStack(spacing: 12) {
            if let followsHighlight {
                swatch(AuroraTheme.gradient(followsHighlight), name: "Highlight", selected: selection == nil) {
                    choose(nil)
                }
            }
            ForEach(Highlight.allCases, id: \.self) { preset in
                swatch(AuroraTheme.gradient(preset), name: preset.displayName, selected: preset == selection) {
                    choose(preset)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func swatch(_ fill: LinearGradient, name: String, selected: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Circle().fill(fill).frame(width: 24, height: 24)
                    .overlay(Circle().stroke(Color.primary, lineWidth: selected ? 2 : 0).padding(-3))
                Text(name).font(.caption2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
