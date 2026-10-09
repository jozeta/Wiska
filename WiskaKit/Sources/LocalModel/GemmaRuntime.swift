import Foundation

/// A model in memory, answering one prompt at a time with fresh chat state.
public protocol LoadedModel: Sendable {
    func respond(system: String, prompt: String, maxTokens: Int) async throws -> String
}

public enum LocalModelError: Error, Equatable {
    case unavailable
    case loadFailed(String)
}

/// Loads the model once (concurrent requests share the load), runs it off the main thread,
/// and lets it go after `idleLimit` without use (~5 GB of memory), handing the memory back.
public actor GemmaRuntime {
    public typealias Loader = @Sendable (URL) async throws -> any LoadedModel

    private let loader: Loader
    private let idleLimit: Duration
    /// Frees what the model library keeps after the model is dropped (MLX's buffer cache).
    private let release: @Sendable () -> Void
    private var onUnload: (@MainActor @Sendable () -> Void)?
    private var model: (any LoadedModel)?
    private var loading: Task<any LoadedModel, Error>?
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

    public func load(from directory: URL) async throws -> any LoadedModel {
        if let model { return model }
        let started = generation
        let task: Task<any LoadedModel, Error>
        if let loading {
            task = loading
        } else {
            let loader = loader
            task = Task { try await loader(directory) }
            loading = task
        }
        let loaded: any LoadedModel
        do {
            loaded = try await task.value
        } catch {
            if generation == started { loading = nil }
            throw LocalModelError.loadFailed(String(describing: error))
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

    public func generate(directory: URL, system: String, prompt: String, maxTokens: Int) async throws -> String {
        let loaded = try await load(from: directory)
        defer { scheduleUnload() }
        return try await loaded.respond(system: system, prompt: prompt, maxTokens: maxTokens)
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
