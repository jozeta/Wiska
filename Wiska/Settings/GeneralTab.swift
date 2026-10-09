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
                Toggle("Show live preview in the notch", isOn: $settings.livePreview)
                Text("The words appear under the waveform as you speak (Apple engine only).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Permissions") {
                LabeledContent("Status", value: model.missingPermissions.isEmpty ? "All granted" : "Setup needed")
                Button("Open Setup…") { OnboardingWindow.open(openWindow) }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
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
