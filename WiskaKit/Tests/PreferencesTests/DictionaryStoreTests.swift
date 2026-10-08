import Core
import Foundation
import Testing
@testable import Preferences

@MainActor
struct DictionaryStoreTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dict-\(UUID().uuidString)")
    var url: URL { dir.appendingPathComponent("dictionary.json") }

    @Test func startsEmptyWithoutAFile() {
        #expect(DictionaryStore(url: url).dictionary == PersonalDictionary())
    }

    @Test func editsPersistAcrossInstances() {
        let store = DictionaryStore(url: url)
        store.addWord("  Kvarnholmen ")
        store.addWord("kvarnholmen")
        store.addWord("Jozeta")
        store.addReplacement(heard: "secure whisper", written: "SecureWispr")
        store.removeWords(at: IndexSet(integer: 1))

        let reloaded = DictionaryStore(url: url)
        #expect(reloaded.dictionary.words == ["Kvarnholmen"])
        #expect(reloaded.dictionary.replacements.map(\.written) == ["SecureWispr"])

        reloaded.removeReplacement(id: reloaded.dictionary.replacements[0].id)
        #expect(DictionaryStore(url: url).dictionary.replacements.isEmpty)
    }

    @Test func corruptFileIsKeptAsideNotOverwritten() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: url)
        let store = DictionaryStore(url: url)
        #expect(store.dictionary == PersonalDictionary())
        let aside = dir.appendingPathComponent("dictionary.corrupt.json")
        #expect(try String(contentsOf: aside, encoding: .utf8) == "{not json")
    }
}
