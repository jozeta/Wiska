import Core
import Foundation
import Testing
@testable import Preferences

@MainActor
struct CommandStoreTests {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("commands-\(UUID().uuidString).json")

    @Test func missingFileStartsWithTheDefaultsAndSavesThem() {
        let store = CommandStore(url: url)
        #expect(store.commands.map(\.phrases) == [["fix"], ["formal"], ["shorter"], ["bullets"]])
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(CommandStore(url: url).commands == store.commands)   // same ids: loaded, not re-seeded
    }

    @Test func deletedDefaultsStayDeleted() {
        let store = CommandStore(url: url)
        for command in store.commands { store.remove(id: command.id) }
        #expect(CommandStore(url: url).commands.isEmpty)
    }

    @Test func addsUpdatesAndPersists() {
        let store = CommandStore(url: url)
        let command = SavedCommand(phrases: ["swedish"], instruction: "Translate to Swedish.")
        store.add(command)
        var edited = command
        edited.instruction = "Translate to Swedish. Keep the tone."
        store.update(edited)
        #expect(CommandStore(url: url).commands.last == edited)
    }

    @Test func emptyCommandIsRemoved() {
        let store = CommandStore(url: url)
        let blank = SavedCommand(phrases: [""], instruction: "")
        store.add(blank)
        store.removeIfEmpty(id: blank.id)
        store.removeIfEmpty(id: store.commands[0].id)   // a real command stays
        #expect(CommandStore(url: url).commands.count == 4)
    }

    @Test func corruptFileIsSetAsideAndDefaultsUsed() throws {
        try Data("not json".utf8).write(to: url)
        #expect(CommandStore(url: url).commands.count == 4)
        let aside = url.deletingLastPathComponent().appendingPathComponent("commands.corrupt.json")
        #expect(FileManager.default.fileExists(atPath: aside.path))
    }
}
