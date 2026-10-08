import SwiftUI

struct MenuContent: View {
    let model: AppModel

    var body: some View {
        Text(model.statusLine)
        Text(model.languageStatus)
        if model.settings.languageMode == .toggle && !model.parakeetUnavailable {
            Button("Switch to \(model.settings.toggleLanguage.other.displayName)") {
                model.switchToggleLanguage()
            }
        }
        if model.parakeetUnavailable {
            Text("Parakeet unavailable — using Apple")
        }
        if !model.missingPermissions.isEmpty {
            Divider()
            ForEach(model.missingPermissions) { permission in
                Button("Allow \(permission.title) \(permission.reason)…") {
                    permission.openSettings()
                }
            }
        }
        Divider()
        Text("Tip: Keyboard settings ▸ “Press 🌐 key to” ▸ Do Nothing")
        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")
        Button("Quit SecureWispr") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
