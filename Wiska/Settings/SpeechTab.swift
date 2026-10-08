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
                ParakeetCard(store: model.parakeetStore) { model.parakeetModelBecameReady() }
                if model.parakeetUnavailable {
                    Text("Parakeet is selected but not ready — Apple is used until it is.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .onChange(of: settings.engine) { model.warmUpParakeetIfSelected() }
            .onChange(of: settings.engineMode) { model.warmUpParakeetIfSelected() }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ParakeetCard: View {
    let store: ParakeetModelStore
    let onReady: () -> Void

    var body: some View {
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
        .onChange(of: store.status) { if store.status == .ready { onReady() } }
    }
}
