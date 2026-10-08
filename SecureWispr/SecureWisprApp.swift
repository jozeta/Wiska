import SwiftUI

@main
struct SecureWisprApp: App {
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
        Window("Dictation History", id: "history") {
            HistoryView(store: model.history)
        }
        Settings {
            SettingsView(model: model)
        }
    }
}
