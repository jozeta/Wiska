import Core
import SwiftUI

struct MenuContent: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

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
        Menu("Cleanup: \(model.settings.cleanupLevel.displayName)") {
            ForEach(CleanupLevel.allCases, id: \.self) { level in
                Button {
                    model.settings.cleanupLevel = level
                } label: {
                    if level == model.settings.cleanupLevel {
                        Label(level.displayName, systemImage: "checkmark")
                    } else {
                        Text(level.displayName)
                    }
                }
            }
        }
        if model.cleanupUnavailable {
            Text("AI cleanup unavailable — using basic cleanup")
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
        Button("History…") {
            NSApp.activate()
            openWindow(id: "history")
        }
        .keyboardShortcut("y")
        Button("Settings…") {
            // A menu-bar-only app isn't active, so SettingsLink would open the window
            // *behind* the frontmost app. Activate first, then raise the window.
            NSApp.activate()
            openSettings()
            DispatchQueue.main.async {
                NSApp.windows
                    .first { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" || $0.title.contains("Settings") }?
                    .orderFrontRegardless()
            }
        }
        .keyboardShortcut(",")
        Button("Quit SecureWispr") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
