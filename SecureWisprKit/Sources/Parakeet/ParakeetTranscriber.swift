import Core
import Foundation

public enum ParakeetError: Error, Equatable {
    case modelNotInstalled
}

/// Parakeet TDT 0.6B v3. Detects the language itself, so the LanguageChoice is ignored.
/// Never downloads: `prepare()` only loads an installed model.
@MainActor
public final class ParakeetTranscriber: Transcriber {
    private let store: ParakeetModelStore
    private let loader: @MainActor (URL) async throws -> any SpeechRecognizerBackend
    private var backend: (any SpeechRecognizerBackend)?
    private var loading: Task<any SpeechRecognizerBackend, Error>?
    private var loadFailure: Error?

    public var isReady: Bool { backend != nil && store.isInstalled }

    public convenience init(store: ParakeetModelStore) {
        self.init(store: store, loader: { try await FluidAudioBackend.load(from: $0) })
    }

    init(store: ParakeetModelStore, loader: @escaping @MainActor (URL) async throws -> any SpeechRecognizerBackend) {
        self.store = store
        self.loader = loader
    }

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
            backend = try await task.value
        } catch {
            loadFailure = error
            throw error
        }
    }

    public func makeSession(language: LanguageChoice) async throws -> any TranscriptionSession {
        try await prepare()
        guard let backend else { throw ParakeetError.modelNotInstalled }
        return ParakeetSession(backend: backend)
    }
}
