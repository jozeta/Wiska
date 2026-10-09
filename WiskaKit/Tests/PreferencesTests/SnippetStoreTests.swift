import Core
import Foundation
import Testing
@testable import Preferences

@MainActor
struct SnippetStoreTests {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("snippets-\(UUID().uuidString).json")

    @Test func addsUpdatesRemovesAndPersists() {
        let store = SnippetStore(url: url)
        let snippet = Snippet(name: "signature", aliases: ["signatur"], text: "Best regards,\nJohan")
        store.add(snippet)
        var edited = snippet
        edited.text = "Cheers,\nJohan"
        store.update(edited)
        #expect(SnippetStore(url: url).snippets == [edited])
        store.remove(id: snippet.id)
        #expect(SnippetStore(url: url).snippets.isEmpty)
    }

    @Test func corruptFileIsSetAside() throws {
        try Data("not json".utf8).write(to: url)
        #expect(SnippetStore(url: url).snippets.isEmpty)
        let aside = url.deletingLastPathComponent().appendingPathComponent("snippets.corrupt.json")
        #expect(FileManager.default.fileExists(atPath: aside.path))
    }

    @Test func spokenNamesSkipBlanks() {
        let snippet = Snippet(name: " Address ", aliases: ["", "adress"], text: "x")
        #expect(snippet.spokenNames == ["Address", "adress"])
    }
}
