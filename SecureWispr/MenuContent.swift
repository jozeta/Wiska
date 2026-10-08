import SwiftUI

struct MenuContent: View {
    let model: AppModel

    var body: some View {
        Text(model.statusLine)
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
