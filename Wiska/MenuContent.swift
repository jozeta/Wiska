import Core
import SwiftUI

struct MenuContent: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Status: what Wiska is doing and how it listens.
        Label(model.statusLine, systemImage: model.menuBarSymbol)
            .onAppear { model.menuOpened() }
        Label(model.languageStatus, systemImage: "globe")
        if let stats = model.statsLine {
            Label(stats, systemImage: "chart.bar")
        }
        if model.parakeetUnavailable {
            Label("Parakeet unavailable — using Apple", systemImage: "exclamationmark.triangle")
        }
        if model.cleanupUnavailable {
            Label("AI cleanup unavailable — using basic cleanup", systemImage: "exclamationmark.triangle")
        }

        // How dictation behaves.
        Divider()
        if model.settings.languageMode == .toggle && model.settings.enabledLanguages.count > 1
            && model.toggleLanguageMatters {
            Button {
                model.switchToggleLanguage()
            } label: {
                Label("Switch to \(model.settings.toggleLanguage.next(in: model.settings.enabledLanguages).displayName)",
                      systemImage: "arrow.left.arrow.right")
            }
        }
        Menu {
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
        } label: {
            Label("Cleanup: \(model.settings.cleanupLevel.displayName)", systemImage: "sparkles")
        }
        if model.modelUpdateAvailable {
            Button { showSettings() } label: {
                Label("Speech model update available…", systemImage: "arrow.down.circle")
            }
        }

        if !model.missingPermissions.isEmpty {
            Divider()
            ForEach(model.missingPermissions) { permission in
                if permission == .inputMonitoring {
                    // Follows Accessibility, from the next launch: nothing to allow by hand.
                    if !model.missingPermissions.contains(.accessibility) {
                        Button { model.relaunch() } label: {
                            Label("Restart Wiska to finish setup", systemImage: "arrow.clockwise")
                        }
                    }
                } else {
                    Button { permission.requestOrOpenSettings() } label: {
                        Label("Allow \(permission.title) \(permission.reason)…", systemImage: "lock.shield")
                    }
                }
            }
        }

        // Your dictations.
        Divider()
        Button {
            model.pasteLastDictation(after: .milliseconds(250))
        } label: {
            Label(model.settings.pasteLastShortcut == .off
                  ? "Paste Last Dictation" : "Paste Last Dictation (\(model.settings.pasteLastShortcut.displayName))",
                  systemImage: "doc.on.clipboard")
        }
        .disabled(model.lastDictation == nil)
        Button { HistoryWindow.open(openWindow) } label: {
            Label("History…", systemImage: "clock.arrow.circlepath")
        }
        .keyboardShortcut("y")

        // Audio files and meetings.
        Divider()
        Button {
            model.transcribeMode = .file
            TranscribeFileWindow.open(openWindow)
        } label: {
            Label("Transcribe Audio File…", systemImage: "waveform.badge.plus")
        }
        Button {
            model.transcribeMode = .meeting
            TranscribeFileWindow.open(openWindow)
        } label: {
            Label(model.meetingRecorder.isRecording ? "Recording Meeting…" : "Record Meeting…",
                  systemImage: model.meetingRecorder.isRecording ? "record.circle.fill" : "person.2.wave.2")
        }

        // Setup.
        Divider()
        Label("Tip: Keyboard settings ▸ “Press 🌐 key to” ▸ Do Nothing", systemImage: "lightbulb")
        Button { OnboardingWindow.open(openWindow) } label: {
            Label("Setup…", systemImage: "checklist")
        }

        // The app.
        Divider()
        if let version = model.updater.availableVersion {
            Button { model.updater.checkForUpdates() } label: {
                Label("Update to Wiska \(version)…", systemImage: "arrow.down.circle.fill")
            }
        } else {
            Button { model.updater.checkForUpdates() } label: {
                Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!model.updater.canCheckForUpdates)
        }
        Button { showSettings() } label: {
            Label("Settings…", systemImage: "gearshape")
        }
        .keyboardShortcut(",")
        Button { NSApp.terminate(nil) } label: {
            Label("Quit Wiska", systemImage: "power")
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
