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

    public init(store: GemmaModelStore, runtime: GemmaRuntime = GemmaRuntime(loader: MLXLoadedModel.load)) {
        self.store = store
        self.runtime = runtime
    }

    public var isAvailable: Bool { store.isInstalled && loadError == nil }

    public func prepare() {
        guard isAvailable, !isLoaded else { return }
        let runtime = runtime
        let directory = store.directory
        Task { [weak self] in
            do {
                _ = try await runtime.load(from: directory)
                self?.isLoaded = true
            } catch {
                self?.failedToLoad(error)
            }
        }
    }

    public func generate(system: String, prompt: String, maxTokens: Int) async throws -> String {
        guard isAvailable else { throw LocalModelError.unavailable }
        do {
            let answer = try await runtime.generate(directory: store.directory, system: system, prompt: prompt,
                                                    maxTokens: maxTokens)
            isLoaded = true
            return answer
        } catch let error as LocalModelError {
            failedToLoad(error)
            throw error
        }
    }

    /// Deletes the model files and forgets a load error (Settings → Remove).
    public func remove() {
        unload()
        loadError = nil
        store.remove()
    }

    public func unload() {
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
