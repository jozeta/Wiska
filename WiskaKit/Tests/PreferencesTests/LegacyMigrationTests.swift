import Foundation
import Testing
@testable import Preferences

final class LegacyMigrationTests {
    let support = FileManager.default.temporaryDirectory.appendingPathComponent("mig-\(UUID().uuidString)")
    let suites = (new: testDefaultsSuite("WiskaMigTests"), old: testDefaultsSuite("WiskaMigLegacy"))
    lazy var defaults = UserDefaults(suiteName: suites.new)!
    lazy var legacy = UserDefaults(suiteName: suites.old)!

    // Throwaway stores and folders live in the temp folder; remove them after every test.
    deinit {
        discardTestDefaults(suites.new)
        discardTestDefaults(suites.old)
        try? FileManager.default.removeItem(at: support)
    }
    var old: URL { support.appendingPathComponent("SecureWispr") }
    var new: URL { support.appendingPathComponent("Wiska") }

    func makeOld() throws {
        try FileManager.default.createDirectory(at: old.appendingPathComponent("Models"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: old.appendingPathComponent("dictionary.json"))
    }

    func run() -> LegacyMigration.Outcome {
        LegacyMigration.run(applicationSupport: support, defaults: defaults, legacyDefaults: legacy)
    }

    @Test func movesOldDataFolder() throws {
        try makeOld()
        #expect(run().movedData)
        #expect(FileManager.default.fileExists(atPath: new.appendingPathComponent("dictionary.json").path))
        #expect(FileManager.default.fileExists(atPath: new.appendingPathComponent("Models").path))
        #expect(!FileManager.default.fileExists(atPath: old.path))
    }

    @Test func keepsBothWhenBothExist() throws {
        try makeOld()
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        #expect(!run().movedData)
        #expect(FileManager.default.fileExists(atPath: old.appendingPathComponent("dictionary.json").path))
        #expect(!FileManager.default.fileExists(atPath: new.appendingPathComponent("dictionary.json").path))
    }

    @Test func copiesOnlyMissingSettings() {
        legacy.set("parakeet", forKey: "engine")
        legacy.set("light", forKey: "cleanupLevel")
        defaults.set("polished", forKey: "cleanupLevel")
        let outcome = run()
        #expect(outcome.copiedKeys == ["engine"])
        #expect(defaults.string(forKey: "engine") == "parakeet")
        #expect(defaults.string(forKey: "cleanupLevel") == "polished")
        #expect(legacy.string(forKey: "engine") == "parakeet")   // never deleted
    }

    @Test func runsOnlyOnce() throws {
        try makeOld()
        _ = run()
        try FileManager.default.removeItem(at: new)                  // user cleared Wiska data
        try makeOld()                                                // old folder reappears
        #expect(run() == LegacyMigration.Outcome(movedData: false, copiedKeys: []))
        #expect(!FileManager.default.fileExists(atPath: new.path))
    }

    @Test func nothingToMigrateIsFine() {
        #expect(run() == LegacyMigration.Outcome(movedData: false, copiedKeys: []))
    }
}
