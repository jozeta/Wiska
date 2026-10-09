import SwiftUI
import KBWhisper

/// Download, status and use of KB-Whisper (Settings → Speech), shown when Swedish is ticked.
struct KBWhisperCard: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        let store = model.kbWhisperStore
        let recognizer = model.kbWhisper
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("KB-Whisper Large (Swedish)")
                    Text("The National Library of Sweden's Whisper, trained on 50,000 hours of Swedish. Re-transcribes Swedish dictations on this Mac. About 1.1 GB, downloaded from Hugging Face only when you click Download.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(KBWhisperRecognizer.statusText(store.status, loaded: recognizer.isLoaded, loadError: recognizer.loadError))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                switch store.status {
                case .notDownloaded:
                    Button("Download") { store.download() }
                case .downloading(let fraction):
                    ProgressView(value: fraction).frame(width: 90)
                    Button("Cancel") { store.cancelDownload() }
                case .ready:
                    Button(recognizer.loadError == nil ? "Remove" : "Remove and download again") {
                        let retry = recognizer.loadError != nil
                        recognizer.remove()
                        settings.useKBWhisper = false
                        if retry { store.download() }
                    }
                case .failed:
                    Button("Retry") { store.download() }
                }
            }
            if store.isInstalled {
                Toggle("Use KB-Whisper for Swedish", isOn: Binding(get: { settings.useKBWhisper }, set: { on in
                    settings.useKBWhisper = on
                    if on { recognizer.prepare() } else { recognizer.unload() }
                }))
                Text("Swedish dictations are transcribed again by KB-Whisper after you release fn; the live preview still comes from your engine.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
