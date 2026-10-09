import AppKit
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
        // Resizable: starts 700 wide (captions and examples rarely wrap), never narrower than 560.
        .frame(minWidth: 560, idealWidth: 700, maxWidth: .infinity)
        // SwiftUI makes Settings windows fixed-size; let the user drag the edges.
        .background(ResizableWindow(minSize: NSSize(width: 560, height: 420)))
    }
}

/// Makes the hosting window resizable (Settings windows aren't, by default).
private struct ResizableWindow: NSViewRepresentable {
    let minSize: NSSize

    func makeNSView(context: Context) -> NSView { WindowHook(minSize: minSize) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowHook: NSView {
        let minSize: NSSize

        init(minSize: NSSize) {
            self.minSize = minSize
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.styleMask.insert(.resizable)
            window.contentMinSize = minSize
        }
    }
}
