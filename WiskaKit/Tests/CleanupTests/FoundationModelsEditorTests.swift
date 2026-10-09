import Core
import FoundationModels
import Testing
@testable import Cleanup

@MainActor
struct FoundationModelsEditorTests {
    nonisolated static var modelAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    @Test func tooLongIsRejectedBeforeTheModel() async {
        let long = Array(repeating: "word", count: FoundationModelsEditor.maxWords + 1).joined(separator: " ")
        await #expect(throws: EditError.tooLong) {
            try await FoundationModelsEditor().edit(long, instruction: "shorten", language: .english)
        }
    }

    @Test func promptCarriesInstructionAndText() {
        let prompt = FoundationModelsEditor.prompt(text: "hey can u send it", instruction: "make it formal")
        #expect(prompt.contains("make it formal"))
        #expect(prompt.contains("hey can u send it"))
        #expect(FoundationModelsEditor.instructions.contains("Output only the edited text"))
    }

    @Test(.enabled(if: modelAvailable), .timeLimit(.minutes(1)))
    func makesTextMoreFormal() async throws {
        let original = "hey can u send it asap"
        let edited = try await FoundationModelsEditor().edit(original, instruction: "make this more formal",
                                                             language: .english)
        #expect(!edited.isEmpty)
        #expect(edited != original)
        #expect(!CleanupGuard.words(edited).contains("u"), "\(edited)")
    }

    @Test func keepsTheSelectionsSurroundingWhitespace() {
        #expect(FoundationModelsEditor.rewrap(original: "hey there\n", edited: "Hello there.") == "Hello there.\n")
        #expect(FoundationModelsEditor.rewrap(original: "  - item one  ", edited: "- Item one")
                == "  - Item one  ")
        #expect(FoundationModelsEditor.rewrap(original: "plain", edited: "\"Plain.\"\n") == "Plain.")
    }

    @Test func longerSelectionsGetMoreTime() {
        #expect(FoundationModelsEditor.timeout(forWords: 20) == .seconds(10))
        #expect(FoundationModelsEditor.timeout(forWords: FoundationModelsEditor.maxWords) > .seconds(30))
        #expect(FoundationModelsEditor.maxWords <= 700)
    }

    @Test func aModelThatIgnoresCancellationStillTimesOut() async {
        let editor = FoundationModelsEditor(isAvailable: { true }, respond: { _ in
            let end = ContinuousClock.now + .seconds(5)
            while ContinuousClock.now < end { try? await Task.sleep(for: .milliseconds(10)) }
            return "too late"
        }, timeout: { _ in .milliseconds(100) })
        let start = ContinuousClock.now
        await #expect(throws: EditError.failed) {
            try await editor.edit("some text", instruction: "shorten", language: nil)
        }
        #expect(ContinuousClock.now - start < .seconds(1))
    }
}
