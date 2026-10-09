import Cleanup
import Core
import Foundation
import Testing
@testable import LocalModel

/// The Compare window's cases through the real models (Xcode only, model downloaded):
/// `TEST_RUNNER_WISKA_REAL_MODEL=1 xcodebuild test -scheme WiskaKit -destination 'platform=macOS'
///  -only-testing:LocalModelTests/BenchmarkRealTests` from WiskaKit/.
@MainActor
struct BenchmarkRealTests {
    nonisolated static var enabled: Bool { ProcessInfo.processInfo.environment["WISKA_REAL_MODEL"] == "1" }

    @Test(.enabled(if: enabled), .timeLimit(.minutes(10)))
    func compareModels() async {
        let gemma = GemmaModel(store: GemmaModelStore())
        var engines: [(String, any TextRewriter, any TextEditor)] = [
            ("Gemma", LocalRewriter(generator: gemma), LocalEditor(generator: gemma)),
        ]
        let apple = FoundationModelsRewriter()
        if apple.isAvailable { engines.insert(("Apple", apple, FoundationModelsEditor()), at: 0) }
        _ = try? await gemma.generate(system: "Reply OK.", prompt: "OK?", maxTokens: 4)   // load first: time answers, not loading
        for (name, rewriter, editor) in engines {
            var passed = 0
            var total = Duration.zero
            for benchmarkCase in ModelBenchmark.cases {
                let result = await ModelBenchmark.run(benchmarkCase, rewriter: rewriter, editor: editor)
                passed += result.passed ? 1 : 0
                total += result.duration
                print("BENCH \(name) #\(benchmarkCase.id) \(result.passed ? "✓" : "✗") \(result.duration) \(result.output.debugDescription)")
            }
            print("BENCH \(name) SUMMARY \(passed)/\(ModelBenchmark.cases.count) avg \(total / ModelBenchmark.cases.count)")
        }
    }
}
