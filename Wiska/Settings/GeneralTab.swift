import Core
import AppKit
import Preferences
import SwiftUI

struct GeneralTab: View {
    let model: AppModel
    @State private var login = LoginItem()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section("Startup") {
                Toggle("Launch Wiska at login", isOn: Binding(get: { login.isEnabled },
                                                               set: { login.setEnabled($0) }))
                if login.needsApproval {
                    HStack {
                        Text("Approve Wiska in System Settings → Login Items.").font(.caption)
                        Button("Open Login Items") { login.openLoginItemsSettings() }
                    }
                }
                if let error = login.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                if login.isOutsideApplications {
                    Text("Starts this copy of Wiska. After moving Wiska to Applications, turn this off and on again.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Dictation") {
                LabeledContent("Dictate", value: "Hold fn, speak, release")
                LabeledContent("Hands-free", value: "Double-tap fn · tap fn to finish · Esc cancels")
                LabeledContent("Edit", value: "Select text, hold fn+⌃, say what to change")
                Picker("Finish hands-free after silence", selection: $settings.handsFreeSilence) {
                    ForEach(SettingsStore.handsFreeSilenceChoices, id: \.self) { seconds in
                        Text(Self.silenceLabel(seconds)).tag(seconds)
                    }
                }
                Picker("After dictation", selection: $settings.outputMode) {
                    ForEach(OutputMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Text(settings.outputMode == .insert
                     ? "The text is pasted where your cursor is."
                     : "The text is only copied — paste it with ⌘V where you want it.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Paste last dictation again", selection: Binding(
                    get: { settings.pasteLastShortcut },
                    set: { settings.pasteLastShortcut = $0; model.applyPasteLastShortcut() })) {
                    ForEach(PasteLastShortcut.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Text("Pastes your last dictation at the cursor again, in any app — handy when it landed in the wrong place. Also in Wiska's menu.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show live preview (Notch Dropdown and Clippy)", isOn: $settings.livePreview)
                Text("The words appear under the waveform as you speak (Apple engine only).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Updates") {
                Toggle("Check for Wiska updates automatically", isOn: Binding(
                    get: { model.updater.checksAutomatically },
                    set: { model.updater.checksAutomatically = $0 }))
                HStack {
                    Button("Check Now") { model.updater.checkForUpdates() }
                        .disabled(!model.updater.canCheckForUpdates)
                    if let checked = model.updater.lastChecked {
                        Text("Last checked \(checked.formatted(.relative(presentation: .named)))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Once a day Wiska asks GitHub whether a newer release exists; it sends nothing about you. An update is checked against Wiska's signing key before it's installed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Permissions") {
                LabeledContent("Status", value: model.missingPermissions.isEmpty ? "All granted" : "Setup needed")
                Button("Open Setup…") { OnboardingWindow.open(openWindow) }
            }
        }
        .formStyle(.grouped)
        .onAppear { login.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            login.refresh()
        }
    }

    private static func silenceLabel(_ seconds: TimeInterval) -> String {
        switch seconds {
        case 0: "Never"
        case ..<60: "\(Int(seconds)) seconds"
        case 60: "1 minute"
        default: "\(Int(seconds / 60)) minutes"
        }
    }
}
