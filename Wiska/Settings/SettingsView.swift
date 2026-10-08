import SwiftUI

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralTab(model: model) }
            Tab("Speech", systemImage: "waveform") { SpeechTab(model: model) }
            Tab("Languages", systemImage: "globe") { LanguagesTab(model: model) }
            Tab("Cleanup", systemImage: "sparkles") { CleanupTab(model: model) }
            Tab("Dictionary", systemImage: "character.book.closed") { DictionaryTab(store: model.dictionaryStore) }
            Tab("History", systemImage: "clock") { HistoryTab(model: model) }
            Tab("Appearance", systemImage: "paintpalette") { AppearanceTab(model: model) }
        }
        .frame(width: 520)
    }
}
