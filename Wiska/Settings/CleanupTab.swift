import Core
import Preferences
import SwiftUI

struct CleanupTab: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section("Cleanup") {
                Picker("Level", selection: $settings.cleanupLevel) {
                    ForEach(CleanupLevel.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(settings.cleanupLevel.summary).font(.caption).foregroundStyle(.secondary)
                Text("Say “new line”, “new paragraph” or “scratch that” (“ny rad”, “nytt stycke”, “stryk det”).")
                    .font(.caption).foregroundStyle(.secondary)
                if model.cleanupUnavailable {
                    Text("Apple Intelligence is unavailable — basic cleanup is used.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}
