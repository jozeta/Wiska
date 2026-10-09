import Foundation
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Gemma through MLX: loaded from the downloaded folder (never from the network).
public struct MLXLoadedModel: LoadedModel {
    let container: ModelContainer

    public static func load(from directory: URL) async throws -> any LoadedModel {
        let container = try await LLMModelFactory.shared.loadContainer(from: directory, using: TransformersTokenizerLoader())
        return MLXLoadedModel(container: container)
    }

    public func respond(system: String, prompt: String, maxTokens: Int) async throws -> String {
        let session = ChatSession(container, instructions: system,
                                  generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0))
        return try await session.respond(to: prompt)
    }
}

/// swift-transformers' tokenizer behind mlx-swift-lm's protocols (what `#huggingFaceTokenizerLoader`
/// would generate, without the macro).
struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        TokenizerBridge(try await AutoTokenizer.from(modelFolder: directory))
    }
}

struct TokenizerBridge: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(messages: [[String: any Sendable]], tools: [[String: any Sendable]]?,
                           additionalContext: [String: any Sendable]?) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
