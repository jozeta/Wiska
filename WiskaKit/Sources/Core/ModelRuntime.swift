import Foundation

public enum ModelRuntimeError: Error, Equatable {
    case unavailable
    case loadFailed(String)
}

/// Loads the model once (concurrent requests share the load), runs it off the main thread,
/// and lets it go after `idleLimit` without use (Gemma ~5 GB, KB-Whisper ~1.5 GB), handing the memory back.
public actor ModelRuntime<Model: Sendable> {
    public typealias Loader = @Sendable (URL) async throws -> Model

    private let loader: Loader
    private let idleLimit: Duration
    /// Frees what the model library keeps after the model is dropped (MLX's buffer cache for Gemma).
    private let release: @Sendable () -> Void
    private var onUnload: (@MainActor @Sendable () -> Void)?
    private var model: Model?
    private var loading: Task<Model, Error>?
    private var idleTask: Task<Void, Never>?
    /// Bumped by every unload: a load that finishes under an older generation is thrown away.
    private var generation = 0

    public init(idleLimit: Duration = .seconds(1_800), release: @escaping @Sendable () -> Void = {},
                loader: @escaping Loader) {
        self.idleLimit = idleLimit
        self.release = release
        self.loader = loader
    }

    /// Called after every unload (idle or asked), so "Loaded" can be cleared.
    public func setOnUnload(_ handler: @escaping @MainActor @Sendable () -> Void) {
        onUnload = handler
    }

    public var isLoaded: Bool { model != nil }

    public func load(from directory: URL) async throws -> Model {
        if let model { return model }
        let started = generation
        let task: Task<Model, Error>
        if let loading {
            task = loading
        } else {
            let loader = loader
            task = Task { try await loader(directory) }
            loading = task
        }
        let loaded: Model
        do {
            loaded = try await task.value
        } catch {
            if generation == started { loading = nil }
            throw ModelRuntimeError.loadFailed(String(describing: error))
        }
        // Unloaded meanwhile (Remove, switching to Apple): nobody wants this model any more.
        guard generation == started else { throw CancellationError() }
        loading = nil
        if model == nil {
            model = loaded
            scheduleUnload()   // also a model loaded early and never used is let go
        }
        return model ?? loaded
    }

    /// Loads if needed, runs `body` on the model, and restarts the idle clock. Calls take turns:
    /// a model may not run twice at once (whisper.cpp crashes), and a request cancelled meanwhile
    /// (its dictation timed out) never runs.
    public func use<T: Sendable>(from directory: URL, _ body: @Sendable (Model) async throws -> T) async throws -> T {
        let loaded = try await load(from: directory)
        try Task.checkCancellation()
        await waitForTurn()
        defer {
            endTurn()
            scheduleUnload()
        }
        try Task.checkCancellation()
        return try await body(loaded)
    }

    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    private func waitForTurn() async {
        guard busy else {
            busy = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }   // the turn is handed over by endTurn
    }

    private func endTurn() {
        if waiting.isEmpty {
            busy = false
        } else {
            waiting.removeFirst().resume()
        }
    }

    public func unload() {
        generation += 1
        idleTask?.cancel()
        idleTask = nil
        loading = nil
        let hadModel = model != nil
        model = nil
        if hadModel { release() }
        if let onUnload { Task { @MainActor in onUnload() } }
    }

    private func scheduleUnload() {
        idleTask?.cancel()
        let limit = idleLimit
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: limit)
            guard !Task.isCancelled else { return }
            await self?.unload()
        }
    }
}
