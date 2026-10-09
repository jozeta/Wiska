import Core
import Parakeet
import Preferences
import SwiftUI

struct SpeechTab: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section("Speech engine") {
                Picker("Engines", selection: $settings.engineMode) {
                    ForEach(EngineMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                switch settings.engineMode {
                case .same:
                    Picker("Engine", selection: $settings.engine) {
                        ForEach(SpeechEngine.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                case .perLanguage:
                    ForEach(settings.enabledLanguages, id: \.self) { language in
                        Picker("\(language.flag) \(language.displayName)",
                               selection: Binding(get: { settings.engine(for: language) },
                                                  set: { settings.setEngine($0, for: language)
                                                         model.warmUpParakeetIfSelected() })) {
                            ForEach(SpeechEngine.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                    }
                }
                ParakeetCard(store: model.parakeetStore, updates: model.modelUpdates, settings: model.settings)
                if model.parakeetUnavailable {
                    Text("Parakeet is selected but not ready — Apple is used until it is.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .onChange(of: settings.engine) { model.warmUpParakeetIfSelected() }
            .onChange(of: settings.engineMode) { model.warmUpParakeetIfSelected() }
        }
        .formStyle(.grouped)
    }
}

private struct ParakeetCard: View {
    let store: ParakeetModelStore
    let updates: ModelUpdateChecker
    let settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Parakeet TDT 0.6B v3")
                Text("On-device, 25 languages. About 470 MB, downloaded from Hugging Face only when you click Download.")
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
        if store.status == .ready {
            @Bindable var settings = settings
            HStack {
                Text(updateStatus).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if case .updateAvailable = updates.state {
                    Button("Download update") { updates.downloadUpdate() }
                }
                Button("Check now") { Task { await updates.checkNow() } }
                    .disabled(updates.state == .checking)
            }
            if case .updateAvailable = updates.state {
                Text("Downloading replaces the current model; Apple is used until the download finishes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Picker("Check for model updates", selection: $settings.modelUpdateInterval) {
                ForEach(SettingsStore.modelUpdateIntervals, id: \.self) { days in
                    Text(Self.intervalLabel(days)).tag(days)
                }
            }
        }
        }
    }

    private var updateStatus: String {
        ModelUpdateChecker.statusText(updates.state, lastCheck: settings.lastModelUpdateCheck)
    }

    static func intervalLabel(_ days: Int) -> String {
        switch days {
        case 0: "Never"
        case 1: "Every day"
        default: "Every \(days) days"
        }
    }
}
