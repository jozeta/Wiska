import Core
import Testing
@testable import Cleanup

@MainActor
struct ModelBenchmarkTests {
    @Test func casesCoverTheSpec() {
        #expect(ModelBenchmark.cases.count == 15)
        #expect(Set(ModelBenchmark.cases.map(\.id)).count == 15)
        #expect(ModelBenchmark.cases.first?.input == "He go to the store yesterday and buyed some milk.")
    }

    @Test func scoringMatchesWordsAlternativesAndSymbols() {
        let grammar = ModelBenchmark.cases[0]
        #expect(grammar.passes("He went to the store yesterday and bought some milk."))
        #expect(!grammar.passes("He went to the store yesterday and buyed some milk."))
        let they = ModelBenchmark.cases[1]   // "They're|They are"
        #expect(they.passes("I have an apple. They are going to the park."))
        let question = ModelBenchmark.cases[9]
        #expect(!question.passes("Can you send me the report by Friday."))
        #expect(question.passes("Can you send me the report by Friday?"))
        let bullets = ModelBenchmark.cases[12]
        #expect(bullets.passes("- Milk\n- Eggs\n- Bread"))
        #expect(!bullets.passes("Milk, eggs and bread"))
        let write = ModelBenchmark.cases[13]
        #expect(!write.passes(">>> I'll be there."))
        // Words, not substrings: "um" isn't found inside "document".
        #expect(ModelBenchmark.cases[7].passes("I think we should meet on Wednesday about the document."))
    }

    @Test func runUsesTheRightModelAndTimesIt() async {
        let rewriter = FakeRewriter()
        rewriter.transform = { _ in "He went to the store yesterday and bought some milk." }
        let editor = FakeTextEditor("apple")
        let result = await ModelBenchmark.run(ModelBenchmark.cases[0], rewriter: rewriter, editor: editor)
        #expect(result.passed)
        #expect(rewriter.grammars == [true])
        #expect(editor.calls == 0)
        let edit = await ModelBenchmark.run(ModelBenchmark.cases[10], rewriter: rewriter, editor: editor)
        #expect(edit.output == "apple: hey can u send it asap")
        #expect(!edit.passed)
        rewriter.error = RewriteError()
        let failed = await ModelBenchmark.run(ModelBenchmark.cases[0], rewriter: rewriter, editor: editor)
        #expect(!failed.passed)
        #expect(failed.output.hasPrefix("Error:"))
    }
}
