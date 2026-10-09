import Foundation
import Testing
@testable import Core

struct SnippetTests {
    @Test func phrasesAreTrimmedAndBlanksSkipped() {
        let snippet = Snippet(phrases: [" insert my address ", "", "infoga min adress"], text: "x")
        #expect(snippet.spokenPhrases == ["insert my address", "infoga min adress"])
    }

    /// Snippets saved by the first version (name + aliases) load as phrases.
    @Test func legacyNameAndAliasesBecomePhrases() throws {
        let json = #"[{"id":"CE1560B5-8AEC-450D-AFD2-6913AFC37233","name":"signature","aliases":["signatur"],"text":"Best regards"}]"#
        let snippets = try JSONDecoder().decode([Snippet].self, from: Data(json.utf8))
        #expect(snippets.first?.phrases == ["signature", "signatur"])
        #expect(snippets.first?.text == "Best regards")
    }

    @Test func problemsExplainWhyASnippetCantWork() {
        #expect(Snippet(phrases: [], text: "x").problems == [.noPhrase])
        #expect(Snippet(phrases: ["insert my name"], text: " ").problems == [.noText])
        #expect(Snippet(phrases: ["signature"], text: "x").problems == [.oneWordPhrase("signature")])
        #expect(Snippet(phrases: ["insert my signature"], text: "x").problems.isEmpty)
    }
}
