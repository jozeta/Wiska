import Foundation
import AppKit
import Cleanup
import Core
import Testing
@testable import LocalModel

/// Gemma's version of CleanupTests/SwedishITRepairLiveTests on a real recording's transcript, then the
/// personal dictionary (Wiska's dictionary.json) the way the cleanup pipeline applies it.
/// `TEST_RUNNER_WISKA_REPAIR_FILE=… xcodebuild test -scheme WiskaKit -destination 'platform=macOS'
///  -only-testing:LocalModelTests/GemmaRepairLiveTests` from WiskaKit/ (MLX's Metal code needs Xcode).
@MainActor
struct GemmaRepairLiveTests {
    nonisolated static var file: String? { ProcessInfo.processInfo.environment["WISKA_REPAIR_FILE"] }

    static let instructions = """
    You correct a Swedish dictation by someone who works in IT. Swedish speech recognition sometimes mishears \
    the English technical terms they mix in. If a word is clearly a misheard IT term, write the term correctly \
    and keep its Swedish ending ("pull requesten", "Kubernetes-klustret"). Terms they use include: deploy, \
    pipeline, pull request, merge, branch, code review, staging, deprecated, endpoint, frontend, backend, API, \
    Jira, Kubernetes, Redis, Datadog, AWS, Azure AD, Elasticsearch, Slack, GitHub Actions. \
    Leave everything else exactly as it is: correct English terms stay English, Swedish words stay Swedish, \
    no rewording. If nothing needs fixing, return the text unchanged. Reply with the text only.
    """

    @Test(.enabled(if: file != nil), .timeLimit(.minutes(10)))
    func gemmaRepairsRecording() async throws {
        let model = GemmaModel(store: GemmaModelStore(), runtime: GemmaRuntime(loader: MLXLoadedModel.load))
        #expect(model.isAvailable)
        let data = (try? Data(contentsOf: AppPaths.file("dictionary.json"))) ?? Data("{}".utf8)
        let dictionary = (try? JSONDecoder().decode(PersonalDictionary.self, from: data)) ?? PersonalDictionary()
        for line in try String(contentsOfFile: Self.file!, encoding: .utf8).split(separator: "\n") {
            let fixed = try await model.generate(system: Self.instructions, prompt: String(line), maxTokens: 300)
            let corrected = DictionaryCorrector.apply(fixed, dictionary: dictionary)
            print("REPAIR \(line)\n    →  \(fixed)\n    ⇒  \(corrected)")
        }
    }

    /// The whole cleanup the app runs (light, Swedish), with the system spell checker as the
    /// app's lexicon; with and without the personal dictionary.
    @Test(.enabled(if: file != nil), .timeLimit(.minutes(10)))
    func pipelineRepairsRecording() async throws {
        let model = GemmaModel(store: GemmaModelStore(), runtime: GemmaRuntime(loader: MLXLoadedModel.load))
        let data = (try? Data(contentsOf: AppPaths.file("dictionary.json"))) ?? Data("{}".utf8)
        let dictionary = (try? JSONDecoder().decode(PersonalDictionary.self, from: data)) ?? PersonalDictionary()
        let isKnown: @MainActor (String) -> Bool = { word in
            ["sv", "en"].contains { NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0, language: $0, wrap: false,
                                                                     inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound }
        }
        func pipeline(_ dictionary: PersonalDictionary) -> CleanupPipeline {
            CleanupPipeline(level: { .light }, rewriter: LocalRewriter(generator: model), dictionary: { dictionary },
                            isKnownWord: isKnown, timeout: .seconds(30))
        }
        let context = DictationContext(language: .swedish)
        for line in try String(contentsOfFile: Self.file!, encoding: .utf8).split(separator: "\n") {
            let alone = try await pipeline(PersonalDictionary()).clean(String(line), context: context)
            let full = try await pipeline(dictionary).clean(String(line), context: context)
            print("PIPELINE \(line)\n    →  \(alone)\n    ⇒  \(full)")
        }
    }
}
