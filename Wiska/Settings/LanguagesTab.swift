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
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}
