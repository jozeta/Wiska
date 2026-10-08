import SwiftUI

/// M1 placeholder: shows the fixed configuration. Real controls arrive in M2.
struct SettingsView: View {
    var body: some View {
        Form {
            LabeledContent("Speech engine", value: "Apple SpeechAnalyzer (on-device)")
            LabeledContent("Language", value: "English")
            LabeledContent("Push-to-talk", value: "Hold fn")
            LabeledContent("Cleanup", value: "Off (arrives in M3)")
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .padding()
    }
}
