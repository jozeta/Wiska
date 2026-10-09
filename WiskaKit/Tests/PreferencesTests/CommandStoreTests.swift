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
        let store = CommandStore(url: url)
        #expect(store.commands.count == 4)
        let aside = try #require(store.setAsideFile)
        #expect(FileManager.default.fileExists(atPath: aside.path))
        #expect(aside.lastPathComponent.hasPrefix("commands.corrupt-"))
    }

    /// Each unreadable file is kept under its own name, and the store says so.
    @Test func corruptFilesAreKeptAndReported() throws {
        try Data("not json".utf8).write(to: url)
        let first = CommandStore(url: url)
        #expect(first.setAsideFile != nil)
        try Data("still not json".utf8).write(to: url)
        let second = CommandStore(url: url)
        #expect(second.setAsideFile != nil)
        #expect(second.setAsideFile != first.setAsideFile)
        #expect(FileManager.default.fileExists(atPath: first.setAsideFile!.path))
        #expect(CommandStore(url: url).setAsideFile == nil)   // a readable file: nothing to report
    }

    /// Closing the tab removes every abandoned command with one save.
    @Test func removeEmptyRemovesAllAtOnce() {
        let store = CommandStore(url: url)
        store.add(SavedCommand(phrases: [""], instruction: ""))
        store.add(SavedCommand(phrases: [], instruction: " "))
        store.removeEmpty()
        #expect(CommandStore(url: url).commands.count == 4)
    }
}
