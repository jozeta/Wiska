import Core
import SwiftUI

struct MenuContent: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.statusLine)
        Text(model.languageStatus)
        if let stats = model.statsLine {
            Text(stats)
        }
        if model.settings.languageMode == .toggle && model.settings.enabledLanguages.count > 1
            && model.toggleLanguageMatters {
            Button("Switch to \(model.settings.toggleLanguage.next(in: model.settings.enabledLanguages).displayName)") {
                model.switchToggleLanguage()
            }
        }
        if model.parakeetUnavailable {
            Text("Parakeet unavailable — using Apple")
        }
        if model.modelUpdateAvailable {
            Button("Speech model update available…") { showSettings() }
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
        Button(model.settings.pasteLastShortcut == .off
               ? "Paste Last Dictation" : "Paste Last Dictation (\(model.settings.pasteLastShortcut.displayName))") {
            model.pasteLastDictation(after: .milliseconds(250))
        }
        .disabled(model.lastDictation == nil)
        Text("Tip: Keyboard settings ▸ “Press 🌐 key to” ▸ Do Nothing")
        Button("Setup…") {
            OnboardingWindow.open(openWindow)
        }
        Button("History…") {
            HistoryWindow.open(openWindow)
        }
        .keyboardShortcut("y")
        Button("Settings…") { showSettings() }
        .keyboardShortcut(",")
        Button("Quit Wiska") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func showSettings() {
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
}
