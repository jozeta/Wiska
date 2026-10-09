import Core
import Foundation

/// A model in memory, answering one prompt at a time with fresh chat state.
public protocol LoadedModel: Sendable {
    func respond(system: String, prompt: String, maxTokens: Int) async throws -> String
}

public typealias LocalModelError = ModelRuntimeError
public typealias GemmaRuntime = ModelRuntime<any LoadedModel>

extension ModelRuntime where Model == any LoadedModel {
    public func generate(directory: URL, system: String, prompt: String, maxTokens: Int) async throws -> String {
        try await use(from: directory) { try await $0.respond(system: system, prompt: prompt, maxTokens: maxTokens) }
    }
}
