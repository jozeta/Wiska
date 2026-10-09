import Core
import Parakeet
import Preferences
import SwiftUI

struct SpeechTab: View {
    let model: AppModel
    @State private var comparingVoice = false

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
                        ForEach(engines(including: settings.engine), id: \.self) { Text($0.displayName).tag($0) }
                    }
                case .perLanguage:
                    ForEach(settings.enabledLanguages, id: \.self) { language in
                        Picker("\(language.flag) \(language.displayName)",
                               selection: Binding(get: { settings.engine(for: language) },
                                                  set: { settings.setEngine($0, for: language)
                                                         model.warmUpParakeetIfSelected() })) {
                            ForEach(engines(including: settings.engine(for: language)), id: \.self) {
                                Text($0.displayName).tag($0)
                            }
                        }
                    }
                }
                if !model.parakeetStore.isInstalled {
                    Text("More speech models (Parakeet, KB-Whisper for Swedish) in the Models tab.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if model.parakeetUnavailable {
                    Text("Parakeet is selected but not ready — Apple is used until it is.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .onChange(of: settings.engine) { model.warmUpParakeetIfSelected() }
            .onChange(of: settings.engineMode) { model.warmUpParakeetIfSelected() }
            if settings.enabledLanguages.contains(.swedish) {
                Section("Swedish") {
                    if model.kbWhisperStore.isInstalled {
                        Toggle("Use KB-Whisper for Swedish", isOn: Binding(get: { settings.useKBWhisper }, set: { on in
                            settings.useKBWhisper = on
                            if on { model.kbWhisper.prepare() } else { model.kbWhisper.unload() }
                        }))
                        Text("Swedish dictations are transcribed again by KB-Whisper after you release fn; the live preview still comes from your engine.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("For fewer Swedish mishearings, download KB-Whisper in the Models tab.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Compare on my voice…") { comparingVoice = true }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $comparingVoice) { VoiceCompareView(model: model) }
    }

    /// Downloaded engines only — plus the current choice, so the picker never shows a blank while
    /// Parakeet is being updated.
    private func engines(including current: SpeechEngine) -> [SpeechEngine] {
        let offered = SpeechEngine.offered(parakeetInstalled: model.parakeetStore.isInstalled)
        return offered.contains(current) || current == .kbWhisper ? offered : offered + [current]
    }
}
