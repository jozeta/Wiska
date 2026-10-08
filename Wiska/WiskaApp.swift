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
            MenuBarLabel(model: model)
        }
        Window(HistoryWindow.title, id: HistoryWindow.id) {
            HistoryView(store: model.history)
        }
        Window(OnboardingWindow.title, id: OnboardingWindow.id) {
            OnboardingView(model: model)
        }
        .windowResizability(.contentSize)
        Settings {
            SettingsView(model: model)
        }
    }
}

private struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if model.menuBarSymbol == "waveform" {
                Image("MenuBarIcon")
            } else {
                Image(systemName: model.menuBarSymbol)
            }
        }
        .onAppear {
            if model.takeOnboardingLaunchOffer() { OnboardingWindow.open(openWindow) }
        }
    }
}
