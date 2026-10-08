import Core
import Foundation
import Observation

public enum ParakeetError: Error, Equatable {
    case modelNotInstalled
}

/// Parakeet TDT 0.6B v3. Detects the language itself, so the LanguageChoice is ignored.
/// Never downloads: `prepare()` only loads an installed model.
/// Observable so Settings and the menu notice when the model finishes loading.
@MainActor @Observable
public final class ParakeetTranscriber: Transcriber {
    @ObservationIgnored private let store: ParakeetModelStore
    @ObservationIgnored private let loader: @MainActor (URL) async throws -> any SpeechRecognizerBackend
    /// The ticked languages, for guessing which one Parakeet heard.
    @ObservationIgnored private let languages: @MainActor () -> [Language]
    private var backend: (any SpeechRecognizerBackend)?
    @ObservationIgnored private var loading: Task<any SpeechRecognizerBackend, Error>?
    @ObservationIgnored private var loadFailure: Error?

    public var isReady: Bool { backend != nil && store.isInstalled }
    public var engine: SpeechEngine { .parakeet }

    public convenience init(store: ParakeetModelStore,
                            languages: @escaping @MainActor () -> [Language] = { Language.allCases }) {
        self.init(store: store, loader: { try await FluidAudioBackend.load(from: $0) }, languages: languages)
    }

    init(store: ParakeetModelStore, loader: @escaping @MainActor (URL) async throws -> any SpeechRecognizerBackend,
         languages: @escaping @MainActor () -> [Language] = { Language.allCases }) {
        self.store = store
        self.loader = loader
        self.languages = languages
        store.onRemove = { [weak self] in self?.unload() }
    }

    /// Drops the loaded model. Sessions already running keep their own reference.
    func unload() {
        loading?.cancel()
        loading = nil
        backend = nil
    }

    /// True after a failed load, until `forgetLoadFailure()`: warming up again would only fail again.
    public var hasLoadFailure: Bool { loadFailure != nil }

    /// Allow another load attempt after a failure (e.g. the model was re-downloaded).
    public func forgetLoadFailure() {
        loadFailure = nil
    }

    /// Loads the installed model once. Concurrent callers share one load, and a failed load
    /// is remembered instead of being retried on every key press (review I2).
    public func prepare() async throws {
        guard store.isInstalled else {
            backend = nil
            throw ParakeetError.modelNotInstalled
        }
        if backend != nil { return }
        if let loadFailure { throw loadFailure }
        if let loading {
            _ = try await loading.value
            return
        }
        let loader = loader
        let directory = store.directory
        let task = Task<any SpeechRecognizerBackend, Error> { try await loader(directory) }
        loading = task
        defer { loading = nil }
        do {
            let loaded = try await task.value
            // Removed while loading: don't hold on to a model that's no longer installed.
            guard store.isInstalled else { throw ParakeetError.modelNotInstalled }
            backend = loaded
        } catch {
            loadFailure = error
            throw error
        }
    }

    public func makeSession(language: LanguageChoice) async throws -> any TranscriptionSession {
        try await prepare()
        guard let backend else { throw ParakeetError.modelNotInstalled }
        return ParakeetSession(backend: backend, languages: languages())
    }
}
