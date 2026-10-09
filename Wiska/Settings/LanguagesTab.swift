import Core
import Preferences
import SwiftUI

struct LanguagesTab: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section("My languages") {
                ForEach(Language.allCases, id: \.self) { language in
                    let ticked = settings.enabledLanguages.contains(language)
                    Toggle("\(language.flag) \(language.displayName)", isOn: Binding(
                        get: { ticked },
                        set: { on in
                            settings.enabledLanguages = on ? settings.enabledLanguages + [language]
                                                           : settings.enabledLanguages.filter { $0 != language }
                            model.tickedLanguagesChanged()
                        }))
                    .disabled(ticked ? settings.enabledLanguages.count == 1
                                     : settings.enabledLanguages.count >= SettingsStore.maxLanguages)
                    if ticked, let error = model.appleInstallError(for: language) {
                        Text("Apple's speech model isn't available: \(error)")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                Text("Up to \(SettingsStore.maxLanguages) languages (Apple's limit). Auto-detect, Toggle and the fn / fn+⇧ languages use only these.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Language") {
                Picker("Mode", selection: $settings.languageMode) {
                    ForEach(LanguageMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                switch settings.languageMode {
                case .autoDetect:
                    Text("Each dictation is matched against your ticked languages; the most confident result is used.")
                        .font(.caption).foregroundStyle(.secondary)
                case .toggle:
                    Picker("Current language", selection: $settings.toggleLanguage) {
                        ForEach(settings.enabledLanguages, id: \.self) { Text("\($0.flag) \($0.displayName)").tag($0) }
                    }
                    Text("Quick-tap fn+⇧ to move to the next ticked language.").font(.caption).foregroundStyle(.secondary)
                case .perLanguageHotkeys:
                    Picker("fn dictates in", selection: $settings.primaryLanguage) {
                        ForEach(settings.enabledLanguages, id: \.self) { Text("\($0.flag) \($0.displayName)").tag($0) }
                    }
                    Picker("fn+⇧ dictates in", selection: $settings.secondaryLanguage) {
                        ForEach(settings.enabledLanguages.filter { $0 != settings.primaryLanguage }, id: \.self) {
                            Text("\($0.flag) \($0.displayName)").tag($0)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 360, idealHeight: 560, maxHeight: .infinity)
    }
}
