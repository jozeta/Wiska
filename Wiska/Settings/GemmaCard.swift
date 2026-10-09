import LocalModel
import SwiftUI

/// Download, status and removal of the Gemma model (Settings → Cleanup).
struct GemmaCard: View {
    let model: AppModel

    var body: some View {
        let store = model.gemmaStore
        let gemma = model.gemma
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Gemma 4 E4B")
                Text("Runs on this Mac: better grammar and Swedish, and works without Apple Intelligence. About 5.2 GB, downloaded from Hugging Face only when you click Download; uses ~5 GB of memory while loaded.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(GemmaModel.statusText(store.status, loaded: gemma.isLoaded, loadError: gemma.loadError))
                    .font(.caption)
                    .foregroundStyle(gemma.loadError != nil || { if case .failed = store.status { true } else { false } }() ? .red : .secondary)
            }
            Spacer()
            switch store.status {
            case .notDownloaded:
                Button("Download") { store.download() }
            case .downloading(let fraction):
                ProgressView(value: fraction).frame(width: 90)
                Button("Cancel") { store.cancelDownload() }
            case .ready:
                if gemma.loadError != nil {
                    Button("Try again") { gemma.retryLoading() }
                    Button("Remove and download again") {
                        gemma.remove()
                        store.download()
                    }
                } else {
                    Button("Remove") {
                        gemma.remove()
                        if model.settings.languageModel == .gemma { model.settings.languageModel = .apple }
                    }
                }
            case .failed:
                Button("Retry") { store.download() }
            }
        }
    }
}
