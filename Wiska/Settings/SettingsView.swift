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
            Tab("Snippets", systemImage: "text.badge.plus") { SnippetsTab(store: model.snippetStore) }
            Tab("History", systemImage: "clock") { HistoryTab(model: model) }
            Tab("Appearance", systemImage: "paintpalette") { AppearanceTab(model: model) }
            Tab("Help", systemImage: "questionmark.circle") { HelpTab(model: model) }
        }
        // 700 wide so captions and examples rarely wrap; 780 tall (fits a 982 pt screen with the
        // menu bar and title bar) so the long tabs need little scrolling.
        .frame(width: 700, height: 780)

    }
}
