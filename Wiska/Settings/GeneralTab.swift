import SwiftUI

struct GeneralTab: View {
    let model: AppModel
    @State private var login = LoginItem()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
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
            Section("Push-to-talk") {
                LabeledContent("Dictate", value: "Hold fn, speak, release")
            }
            Section("Permissions") {
                LabeledContent("Status", value: model.missingPermissions.isEmpty ? "All granted" : "Setup needed")
                Button("Open Setup…") { OnboardingWindow.open(openWindow) }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { login.refresh() }
    }
}
