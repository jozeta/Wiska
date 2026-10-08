import SwiftUI

@main
struct WiskaApp: App {
    @State private var model: AppModel

    init() {
        let model = AppModel()
        model.start()
        _model = State(initialValue: model)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.menuBarSymbol)
        }
        Window(HistoryWindow.title, id: HistoryWindow.id) {
            HistoryView(store: model.history)
        }
        Settings {
            SettingsView(model: model)
        }
    }
}
