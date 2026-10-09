import Core
import Testing
@testable import Cleanup

@MainActor
final class FakeTextEditor: TextEditor {
    let name: String
    var error: EditError?
    private(set) var calls = 0
    init(_ name: String) { self.name = name }
    func edit(_ text: String, instruction: String, language: Language?) async throws -> String {
        calls += 1
        if let error { throw error }
        return "\(name): \(text)"
    }
    func write(instruction: String, context: String?, language: Language?) async throws -> String {
        calls += 1
        if let error { throw error }
        return "\(name) wrote"
    }
}

@MainActor
struct SwitchingModelTests {
    func rewriters() -> (apple: FakeRewriter, local: FakeRewriter) {
        let apple = FakeRewriter()
        apple.transform = { "apple: \($0)" }
        let local = FakeRewriter()
        local.transform = { "gemma: \($0)" }
        return (apple, local)
    }

    @Test func usesTheChosenModel() async throws {
        let (apple, local) = rewriters()
        var choice = LanguageModelChoice.gemma
        let switching = SwitchingRewriter(choice: { choice }, apple: apple, local: local)
        #expect(try await switching.rewrite("hi", level: .light, language: nil, style: .formal, grammar: false) == "gemma: hi")
        choice = .apple
        #expect(try await switching.rewrite("hi", level: .light, language: nil, style: .formal, grammar: false) == "apple: hi")
    }

    @Test func unavailableChoiceUsesTheOther() async throws {
        let (apple, local) = rewriters()
        local.isAvailable = false
        let switching = SwitchingRewriter(choice: { .gemma }, apple: apple, local: local)
        #expect(try await switching.rewrite("hi", level: .light, language: nil, style: .formal, grammar: false) == "apple: hi")
        apple.isAvailable = false
        #expect(!switching.isAvailable)
        local.isAvailable = true
        #expect(SwitchingRewriter(choice: { .apple }, apple: apple, local: local).isAvailable)   // no Apple Intelligence
    }

    @Test func anErrorRetriesTheOtherModelOnce() async throws {
        let (apple, local) = rewriters()
        local.error = RewriteError()
        let switching = SwitchingRewriter(choice: { .gemma }, apple: apple, local: local)
        #expect(try await switching.rewrite("hi", level: .light, language: nil, style: .formal, grammar: true) == "apple: hi")
        apple.error = RewriteError()
        await #expect(throws: RewriteError.self) {
            try await switching.rewrite("hi", level: .light, language: nil, style: .formal, grammar: true)
        }
    }

    @Test func timeoutAndPrewarmFollowTheModelInUse() {
        let apple = FakeRewriter()
        let generator = FakeGenerator()
        let local = LocalRewriter(generator: generator)
        let switching = SwitchingRewriter(choice: { .gemma }, apple: apple, local: local)
        #expect(switching.preferredTimeout == .milliseconds(2_500))
        switching.prewarm(level: .light, grammar: true)
        #expect(generator.prepared == 1)
        #expect(apple.prewarmed.isEmpty)
        generator.isAvailable = false
        #expect(switching.preferredTimeout == nil)   // Apple: the pipeline's own budget
    }

    @Test func editorFallsBackOnFailureButNotOnTooLong() async throws {
        let apple = FakeTextEditor("apple")
        let local = FakeTextEditor("gemma")
        let editor = SwitchingEditor(choice: { .gemma }, apple: apple, local: local,
                                     appleAvailable: { true }, localAvailable: { true })
        #expect(try await editor.edit("x", instruction: "y", language: nil) == "gemma: x")
        local.error = .failed
        #expect(try await editor.edit("x", instruction: "y", language: nil) == "apple: x")
        #expect(try await editor.write(instruction: "y", context: nil, language: nil) == "apple wrote")
        local.error = .tooLong
        await #expect(throws: EditError.tooLong) { try await editor.edit("x", instruction: "y", language: nil) }
        let none = SwitchingEditor(choice: { .apple }, apple: apple, local: local,
                                   appleAvailable: { false }, localAvailable: { false })
        await #expect(throws: EditError.unavailable) { try await none.edit("x", instruction: "y", language: nil) }
    }
}
