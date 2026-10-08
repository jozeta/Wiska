import Core
import Preferences
import SwiftUI

struct LanguagesTab: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        Form {
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
        .fixedSize(horizontal: false, vertical: true)
    }
}
