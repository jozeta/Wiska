import Core
import Preferences
import SwiftUI

struct HistoryTab: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section("History") {
                Picker("Keep history", selection: $settings.historyRetention) {
                    ForEach(HistoryRetention.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .onChange(of: settings.historyRetention) { model.applyRetention() }
                Text("Stored only on this Mac. Off deletes all history immediately.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open History…") { HistoryWindow.open(openWindow) }
            }
        }
        .formStyle(.grouped)
    }
}
