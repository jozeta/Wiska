import Core
import Foundation
import Observation

/// Gemma 4 E4B as Wiska's local model: available once downloaded and loadable.
@MainActor @Observable
public final class GemmaModel: LocalGenerator {
    private static let log = Log.logger("LocalModel")

    public let store: GemmaModelStore
    @ObservationIgnored private let runtime: GemmaRuntime
    public private(set) var isLoaded = false
    /// Why the model couldn't be loaded; cleared by removing it.
    public private(set) var loadError: String?

    /// Bumped by remove() and unload(): a load or answer that finishes afterwards is old news.
    @ObservationIgnored private var epoch = 0

    public init(store: GemmaModelStore,
                runtime: GemmaRuntime = GemmaRuntime(release: MLXLoadedModel.releaseMemory, loader: MLXLoadedModel.load)) {
        self.store = store
        self.runtime = runtime
        // The runtime lets the model go after 30 idle minutes: "Loaded" must follow, and the next
        // fn press must load it again.
        let unloaded: @MainActor @Sendable () -> Void = { [weak self] in self?.isLoaded = false }
        Task { await runtime.setOnUnload(unloaded) }
    }

    public var isAvailable: Bool { store.isInstalled && loadError == nil }

    /// Loads in the background (fn press). Cheap when the model is already in memory.
    public func prepare() {
        guard isAvailable else { return }
        let runtime = runtime
        let directory = store.directory
        let started = epoch
        Task { [weak self] in
            do {
                _ = try await runtime.load(from: directory)
                guard let self, self.epoch == started else { return }
                self.isLoaded = true
            } catch {
                guard let self, self.epoch == started else { return }
                self.failedToLoad(error)
            }
        }
    }

    public func generate(system: String, prompt: String, maxTokens: Int) async throws -> String {
        guard isAvailable else { throw LocalModelError.unavailable }
        let started = epoch
        do {
            let answer = try await runtime.generate(directory: store.directory, system: system, prompt: prompt,
                                                    maxTokens: maxTokens)
            if epoch == started { isLoaded = true }
            return answer
        } catch let error as LocalModelError {
            if epoch == started { failedToLoad(error) }
            throw error
        }
    }

    /// Forgets a load error and tries again, without downloading again (Settings → Try again).
    public func retryLoading() {
        loadError = nil
        prepare()
    }

    /// Deletes the model files and forgets a load error (Settings → Remove).
    public func remove() {
        unload()
        loadError = nil
        store.remove()
    }

    /// Lets the model go now (Remove, or switching to Apple Intelligence).
    public func unload() {
        epoch += 1
        isLoaded = false
        let runtime = runtime
        Task { await runtime.unload() }
    }

    private func failedToLoad(_ error: Error) {
        guard case LocalModelError.loadFailed(let reason) = error else { return }
        Self.log.error("gemma could not load: \(reason, privacy: .public)")
        loadError = reason
        isLoaded = false
    }

    /// The Settings card's status line.
    public static func statusText(_ status: GemmaModelStore.Status, loaded: Bool, loadError: String?) -> String {
        switch status {
        case .notDownloaded: "Not downloaded"
        case .downloading(let fraction): "Downloading \(Int(fraction * 100)) %"
        case .failed(let message): message
        case .ready:
            if let loadError { "Couldn't load: \(loadError)" } else if loaded { "Loaded" } else { "Ready" }
        }
    }
}

/// Update checks (Settings → Cleanup): through the model, so replacing it also lets the old one
/// go from memory.
extension GemmaModel: UpdatableModelStore {
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
