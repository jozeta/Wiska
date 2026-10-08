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

    public var isReady: Bool { backend != nil && store.isInstalled }

    public convenience init(store: ParakeetModelStore) {
        self.init(store: store, loader: { try await FluidAudioBackend.load(from: $0) })
    }

    init(store: ParakeetModelStore, loader: @escaping @MainActor (URL) async throws -> any SpeechRecognizerBackend) {
        self.store = store
        self.loader = loader
    }

    public func prepare() async throws {
        guard store.isInstalled else {
            backend = nil
            throw ParakeetError.modelNotInstalled
        }
        if backend == nil { backend = try await loader(store.directory) }
    }

    public func makeSession(language: LanguageChoice) async throws -> any TranscriptionSession {
        try await prepare()
        guard let backend else { throw ParakeetError.modelNotInstalled }
        return ParakeetSession(backend: backend)
    }
}
