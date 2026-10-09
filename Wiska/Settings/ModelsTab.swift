import Core
import KBWhisper
import LocalModel
import Parakeet
import Preferences
import SwiftUI

/// Every downloadable model in one place: download, remove, and update checks. The other tabs
/// only offer models that are downloaded.
struct ModelsTab: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                Text("Models run on this Mac and are downloaded from Hugging Face only when you click Download. Apple's own speech recognition and Apple Intelligence need no download.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Speech recognition") {
                ParakeetModelCard(model: model)
                KBWhisperModelCard(model: model)
            }
            Section("Cleanup and commands") {
                GemmaModelCard(model: model)
            }
            Section("Updates") {
                Picker("Check for model updates", selection: $settings.modelUpdateInterval) {
                    ForEach(SettingsStore.modelUpdateIntervals, id: \.self) { days in
                        Text(Self.intervalLabel(days)).tag(days)
                    }
                }
                Text("Wiska only checks; an update is downloaded when you click Download update.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    static func intervalLabel(_ days: Int) -> String {
        switch days {
        case 0: "Never"
        case 1: "Every day"
        default: "Every \(days) days"
        }
    }
}

/// Name, what it's for, and its status line.
private struct ModelHeader: View {
    let title: String
    let purpose: String
    let status: String
    let isError: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(purpose).font(.caption).foregroundStyle(.secondary)
            Text(status).font(.caption).foregroundStyle(isError ? .red : .secondary)
        }
    }
}

/// "Up to date · checked 2 days ago", Check now, and Download update when there's one.
private struct UpdateRow: View {
    let checker: ModelUpdateChecker
    let lastCheck: Date?
    let replaces: String

    var body: some View {
        HStack {
            Text(ModelUpdateChecker.statusText(checker.state, lastCheck: lastCheck))
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            if case .updateAvailable = checker.state {
                Button("Download update") { checker.downloadUpdate() }
            }
            Button("Check now") { Task { await checker.checkNow() } }
                .disabled(checker.state == .checking)
        }
        if case .updateAvailable = checker.state {
            Text("Downloading replaces the current model; \(replaces) is used until it finishes.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ParakeetModelCard: View {
    let model: AppModel

    var body: some View {
        let store = model.parakeetStore
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ModelHeader(title: "Parakeet TDT 0.6B v3",
                            purpose: "Speech recognition in 25 languages; choose it in the Speech tab. About 470 MB.",
                            status: Self.status(store.status), isError: { if case .failed = store.status { true } else { false } }())
                Spacer()
                switch store.status {
                case .notDownloaded: Button("Download") { store.download() }
                case .downloading(let fraction):
                    ProgressView(value: fraction).frame(width: 90)
                    Button("Cancel") { store.cancelDownload() }
                case .ready: Button("Remove") { model.removeParakeet() }
                case .failed: Button("Try again") { store.download() }
                }
            }
            if store.isInstalled {
                UpdateRow(checker: model.modelUpdates, lastCheck: model.settings.lastModelUpdateCheck, replaces: "Apple")
            }
        }
    }

    static func status(_ status: ParakeetModelStore.Status) -> String {
        switch status {
        case .notDownloaded: "Not downloaded"
        case .downloading(let fraction): "Downloading \(Int(fraction * 100)) %"
        case .ready: "Ready"
        case .failed(let message): message
        }
    }
}

private struct KBWhisperModelCard: View {
    let model: AppModel

    var body: some View {
        let store = model.kbWhisperStore
        let recognizer = model.kbWhisper
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ModelHeader(title: "KB-Whisper Large (Swedish)",
                            purpose: "The National Library of Sweden's Whisper re-transcribes Swedish dictations; switch it on in the Speech tab. About 1.1 GB.",
                            status: KBWhisperRecognizer.statusText(store.status, loaded: recognizer.isLoaded,
                                                                   loadError: recognizer.loadError),
                            isError: recognizer.loadError != nil || { if case .failed = store.status { true } else { false } }())
                Spacer()
                switch store.status {
                case .notDownloaded: Button("Download") { store.download() }
                case .downloading(let fraction):
                    ProgressView(value: fraction).frame(width: 90)
                    Button("Cancel") { store.cancelDownload() }
                case .ready:
                    if recognizer.loadError != nil {
                        Button("Remove and download again") {
                            model.removeKBWhisper()
                            store.download()
                        }
                    } else {
                        Button("Remove") { model.removeKBWhisper() }
                    }
                case .failed: Button("Try again") { store.download() }
                }
            }
            if store.isInstalled, recognizer.loadError == nil {
                UpdateRow(checker: model.kbWhisperUpdates, lastCheck: model.settings.lastKBWhisperUpdateCheck,
                          replaces: "your speech engine's text")
            }
        }
    }
}

private struct GemmaModelCard: View {
    let model: AppModel

    var body: some View {
        let store = model.gemmaStore
        let gemma = model.gemma
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ModelHeader(title: "Gemma 4 E4B",
                            purpose: "Cleanup, grammar and command mode, also without Apple Intelligence; choose it in the Cleanup tab. About 5.2 GB, ~5 GB of memory while loaded.",
                            status: GemmaModel.statusText(store.status, loaded: gemma.isLoaded, loadError: gemma.loadError),
                            isError: gemma.loadError != nil || { if case .failed = store.status { true } else { false } }())
                Spacer()
                switch store.status {
                case .notDownloaded: Button("Download") { store.download() }
                case .downloading(let fraction):
                    ProgressView(value: fraction).frame(width: 90)
                    Button("Cancel") { store.cancelDownload() }
                case .ready:
                    if gemma.loadError != nil {
                        Button("Try again") { gemma.retryLoading() }
                        Button("Remove and download again") {
                            model.removeGemma()
                            store.download()
                        }
                    } else {
                        Button("Remove") { model.removeGemma() }
                    }
                case .failed: Button("Try again") { store.download() }
                }
            }
            if store.isInstalled, gemma.loadError == nil {
                UpdateRow(checker: model.gemmaUpdates, lastCheck: model.settings.lastGemmaUpdateCheck,
                          replaces: "Apple Intelligence")
            }
        }
    }
}
