import Core
import Testing
@testable import Cleanup

struct CodeVocabularyTests {
    @Test(arguments: [
        ("Get status.", "git status."),
        ("get commit dash m fix", "git commit dash m fix"),
        ("Kit status", "git status"),
        ("get push and then get pull", "git push and then git pull"),
    ])
    func misheardGitBecomesGit(input: String, expected: String) {
        #expect(CodeVocabulary.apply(input) == expected)
    }

    @Test func getWithoutAGitCommandStays() {
        #expect(CodeVocabulary.apply("get the logs") == "get the logs")
        #expect(CodeVocabulary.apply("forget status") == "forget status")
    }

    @MainActor @Test func onlyTheCodeCategory() async throws {
        let rewriter = FakeRewriter()
        rewriter.isAvailable = false
        let pipeline = CleanupPipeline(level: { .polished }, rewriter: rewriter, timeout: .seconds(5))
        #expect(try await pipeline.clean("Get status.", context: DictationContext(category: .code)) == "git status")
        #expect(try await pipeline.clean("Get status updates from Anna.", context: DictationContext(category: .other))
                == "Get status updates from Anna.")
    }
}
