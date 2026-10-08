import Core
import Parakeet
import Preferences
import SwiftUI

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section("Speech engine") {
                Picker("Engine", selection: $settings.engine) {
                    ForEach(SpeechEngine.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .onChange(of: settings.engine) { model.warmUpParakeetIfSelected() }
                ParakeetCard(store: model.parakeetStore) { model.warmUpParakeetIfSelected() }
                if model.parakeetUnavailable {
                    Text("Parakeet is selected but not ready — Apple is used until it is.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Language") {
                Picker("Mode", selection: $settings.languageMode) {
                    ForEach(LanguageMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                switch settings.languageMode {
                case .autoDetect:
                    Text("Each dictation is transcribed in English and Svenska; the more confident result is used.")
                        .font(.caption).foregroundStyle(.secondary)
                case .toggle:
                    Picker("Current language", selection: $settings.toggleLanguage) {
                        ForEach(Language.allCases, id: \.self) { Text("\($0.flag) \($0.displayName)").tag($0) }
                    }
                    Text("Quick-tap fn+⇧ to switch.").font(.caption).foregroundStyle(.secondary)
                case .perLanguageHotkeys:
                    Picker("fn dictates in", selection: $settings.primaryLanguage) {
                        ForEach(Language.allCases, id: \.self) { Text("\($0.flag) \($0.displayName)").tag($0) }
                    }
                    Text("fn+⇧ dictates in \(settings.primaryLanguage.other.displayName).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Push-to-talk") {
                LabeledContent("Dictate", value: "Hold fn, speak, release")
                LabeledContent("Cleanup", value: "Off (arrives in M3)")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding()
    }
}

private struct ParakeetCard: View {
    let store: ParakeetModelStore
    let onReady: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Parakeet TDT 0.6B v3")
                Text("On-device, 25 languages. Downloaded from Hugging Face only when you click Download.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            switch store.status {
            case .notDownloaded:
                Button("Download") { store.download() }
            case .downloading(let fraction):
                ProgressView(value: fraction).frame(width: 90)
                Button("Cancel") { store.cancelDownload() }
            case .ready:
                Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Remove") { store.remove() }
            case .failed(let message):
                Text(message).font(.caption).foregroundStyle(.red).lineLimit(2)
                Button("Retry") { store.download() }
            }
        }
        .onChange(of: store.status) { if store.status == .ready { onReady() } }
    }
}
