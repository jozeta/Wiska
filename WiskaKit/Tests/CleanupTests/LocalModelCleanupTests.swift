import Core
import Testing
@testable import Cleanup

@MainActor
final class FakeGenerator: LocalGenerator {
    var isAvailable = true
    var reply: (String, String) -> String = { _, prompt in prompt }
    var error: Error?
    var delay: Duration = .zero
    private(set) var prepared = 0
    private(set) var systems: [String] = []
    private(set) var maxTokens: [Int] = []
    func prepare() { prepared += 1 }
    func generate(system: String, prompt: String, maxTokens: Int) async throws -> String {
        systems.append(system)
        self.maxTokens.append(maxTokens)
        if delay > .zero { try await Task.sleep(for: delay) }
        if let error { throw error }
        return reply(system, prompt)
    }
}

@MainActor
struct LocalModelCleanupTests {
    @Test func outputLosesThinkingAndChatTokens() {
        #expect(LocalOutput.clean("<|channel>thought\nlet me think\n<channel|>He went home.") == "He went home.")
        #expect(LocalOutput.clean("He went home.<turn|>") == "He went home.")
        #expect(LocalOutput.clean("  He went home.  ") == "He went home.")
    }

    @Test func rewriterUsesTheSharedPromptsAndPrepares() async throws {
        let generator = FakeGenerator()
        generator.reply = { _, _ in "He went to the store.<turn|>" }
        let rewriter = LocalRewriter(generator: generator)
        rewriter.prewarm(level: .light, grammar: true)
        let output = try await rewriter.rewrite("he go to the store", level: .light, language: .english,
                                                style: .formal, grammar: true)
        #expect(output == "He went to the store.")
        #expect(generator.prepared == 1)
        #expect(generator.systems == [CleanupPrompts.instructions(for: .light, language: .english, style: .formal,
                                                                  grammar: true)])
        #expect(rewriter.preferredTimeout == .milliseconds(2_500))
    }

    @Test func rewriterFollowsTheGeneratorsAvailability() {
        let generator = FakeGenerator()
        generator.isAvailable = false
        #expect(!LocalRewriter(generator: generator).isAvailable)
    }

    @Test func editorEditsAndWritesWithSharedPostProcessing() async throws {
        let generator = FakeGenerator()
        generator.reply = { system, _ in
            system == EditPrompts.instructions ? "\"Could you send it?\"" : ">>> I'll be there at three."
        }
        let editor = LocalEditor(generator: generator)
        #expect(try await editor.edit("can u send it", instruction: "formal", language: nil) == "Could you send it?")
        #expect(try await editor.write(instruction: "reply", context: "Coming?\n\n[cursor]", language: nil)
                == "I'll be there at three.")
    }

    @Test func editorMapsErrors() async {
        let generator = FakeGenerator()
        generator.isAvailable = false
        let off = LocalEditor(generator: generator)
        await #expect(throws: EditError.unavailable) { try await off.edit("x", instruction: "y", language: nil) }
        let failing = FakeGenerator()
        failing.error = CancellationError()
        await #expect(throws: EditError.failed) {
            try await LocalEditor(generator: failing).write(instruction: "y", context: nil, language: nil)
        }
        let slow = FakeGenerator()
        slow.delay = .seconds(5)
        await #expect(throws: EditError.failed) {
            try await LocalEditor(generator: slow, timeout: { _ in .milliseconds(50) }).edit("x", instruction: "y", language: nil)
        }
        let long = Array(repeating: "word", count: EditPrompts.maxWords + 1).joined(separator: " ")
        await #expect(throws: EditError.tooLong) {
            try await LocalEditor(generator: FakeGenerator()).edit(long, instruction: "y", language: nil)
        }
    }
}
