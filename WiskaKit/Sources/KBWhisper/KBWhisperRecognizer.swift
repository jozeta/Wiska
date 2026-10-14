import Core
import Foundation
import Observation

/// KB-Whisper as Wiska's Swedish second pass: available once downloaded and loadable.
@MainActor @Observable
public final class KBWhisperRecognizer: BatchRecognizer {
    private static let log = Log.logger("Whisper")

    public let store: KBWhisperModelStore
    @ObservationIgnored private let runtime: ModelRuntime<any WhisperModel>
    public private(set) var isLoaded = false
    public private(set) var loadError: String?
    /// Bumped by remove() and unload(): a load that finishes afterwards is old news.
    @ObservationIgnored private var epoch = 0

    public convenience init(store: KBWhisperModelStore) {
        self.init(store: store, runtime: ModelRuntime { file in try WhisperContext.load(from: file) })
    }

    init(store: KBWhisperModelStore, runtime: ModelRuntime<any WhisperModel>) {
        self.store = store
        self.runtime = runtime
        let unloaded: @MainActor @Sendable () -> Void = { [weak self] in self?.isLoaded = false }
        Task { await runtime.setOnUnload(unloaded) }
    }

    public var isReady: Bool { store.isInstalled && loadError == nil }

    /// Settings → Models → "Free memory after" (nil: keep until Wiska quits).
    public func setIdleLimit(_ limit: Duration?) {
        let runtime = runtime
        Task { await runtime.setIdleLimit(limit) }
    }

    public func prepare() {
        guard isReady else { return }
        let runtime = runtime
        let file = store.modelFile
        let started = epoch
        Task { [weak self] in
            do {
                _ = try await runtime.load(from: file)
                guard let self, self.epoch == started else { return }
                self.isLoaded = true
            } catch {
                guard let self, self.epoch == started else { return }
                self.failedToLoad(error)
            }
        }
    }

    public func transcribe(_ samples: [Float], language: Language) async throws -> String {
        try await transcribe(samples, language: language, prompt: nil)
    }

    /// `prompt`: text in the vocabulary and style to expect, which Whisper leans towards.
    public func transcribe(_ samples: [Float], language: Language, prompt: String?) async throws -> String {
        guard language == .swedish else { throw ModelRuntimeError.unavailable }   // KB-Whisper is Swedish
        guard isReady else { throw ModelRuntimeError.unavailable }
        let started = epoch
        do {
            let text = try await runtime.use(from: store.modelFile) { try $0.transcribe(samples, language: "sv", prompt: prompt) }
            if epoch == started { isLoaded = true }
            return text
        } catch let error as ModelRuntimeError {
            if epoch == started { failedToLoad(error) }
            throw error
        }
    }

    public func remove() {
        unload()
        loadError = nil
        store.remove()
    }

    public func unload() {
        epoch += 1
        isLoaded = false
        let runtime = runtime
        Task { await runtime.unload() }
    }

    private func failedToLoad(_ error: Error) {
        guard case ModelRuntimeError.loadFailed(let reason) = error else { return }
        Self.log.error("kb-whisper could not load: \(reason, privacy: .public)")
        loadError = reason
        isLoaded = false
    }

    /// The Settings card's status line.
    public static func statusText(_ status: KBWhisperModelStore.Status, loaded: Bool, loadError: String?) -> String {
        switch status {
        case .notDownloaded: "Not downloaded"
        case .downloading(let fraction): "Downloading \(Int(fraction * 100)) %"
        case .failed(let message): message
        case .ready:
            if let loadError { "Couldn't load: \(loadError)" } else if loaded { "Loaded" } else { "Ready" }
        }
    }
}

/// Update checks (Settings → Models): through the recognizer, so replacing the model also lets
/// the old one go from memory.
extension KBWhisperRecognizer: UpdatableModelStore {
    public var isInstalled: Bool { store.isInstalled }
    public var isDownloading: Bool {
        if case .downloading = store.status { true } else { false }
    }
    public var installedRevision: String? { store.installedRevision }
    public var installedAt: Date? { store.installedAt }
    public var installedComponents: Set<String> { store.installedComponents }
    public func recordRevision(_ fingerprint: String) { store.recordRevision(fingerprint) }
    public func startDownload() { store.download() }
}
