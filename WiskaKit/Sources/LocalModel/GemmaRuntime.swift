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
/// and lets it go after `idleLimit` without use (~5 GB of memory).
public actor GemmaRuntime {
    public typealias Loader = @Sendable (URL) async throws -> any LoadedModel

    private let loader: Loader
    private let idleLimit: Duration
    private var model: (any LoadedModel)?
    private var loading: Task<any LoadedModel, Error>?
    private var idleTask: Task<Void, Never>?

    public init(idleLimit: Duration = .seconds(1_800), loader: @escaping Loader) {
        self.idleLimit = idleLimit
        self.loader = loader
    }

    public var isLoaded: Bool { model != nil }

    public func load(from directory: URL) async throws -> any LoadedModel {
        if let model { return model }
        if let loading {   // a second request while loading: the same load, the same error
            do { return try await loading.value } catch { throw LocalModelError.loadFailed(String(describing: error)) }
        }
        let loader = loader
        let task = Task { try await loader(directory) }
        loading = task
        defer { loading = nil }
        do {
            let loaded = try await task.value
            model = loaded
            return loaded
        } catch {
            throw LocalModelError.loadFailed(String(describing: error))
        }
    }

    public func generate(directory: URL, system: String, prompt: String, maxTokens: Int) async throws -> String {
        let loaded = try await load(from: directory)
        defer { scheduleUnload() }
        return try await loaded.respond(system: system, prompt: prompt, maxTokens: maxTokens)
    }

    public func unload() {
        idleTask?.cancel()
        model = nil
    }

    private func scheduleUnload() {
        idleTask?.cancel()
        let limit = idleLimit
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: limit)
            guard !Task.isCancelled else { return }
            await self?.dropModel()
        }
    }

    private func dropModel() {
        model = nil
    }
}
