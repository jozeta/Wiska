import Foundation
import Testing
@testable import LocalModel

/// `TEST_RUNNER_WISKA_REAL_MODEL=1 xcodebuild test -scheme WiskaKit-Package -destination 'platform=macOS'
///  -only-testing:LocalModelTests/GemmaRealTests` from WiskaKit/ (MLX's Metal code needs Xcode).
@MainActor
struct GemmaRealTests {
    nonisolated static var enabled: Bool { ProcessInfo.processInfo.environment["WISKA_REAL_MODEL"] == "1" }

    @Test(.enabled(if: enabled), .timeLimit(.minutes(5)))
    func fixesGrammarWithTheRealModel() async throws {
        let model = GemmaModel(store: GemmaModelStore(), runtime: GemmaRuntime(loader: MLXLoadedModel.load))
        #expect(model.isAvailable)
        let start = ContinuousClock.now
        let answer = try await model.generate(
            system: "Fix the grammar of the user's text. Output only the corrected text.",
            prompt: "He go to the store yesterday and buyed some milk.", maxTokens: 64)
        print("GEMMA:", answer.debugDescription, ContinuousClock.now - start)
        #expect(answer.contains("went") && answer.contains("bought"), "\(answer)")
    }
}
