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
}
