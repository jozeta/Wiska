import Core
import Foundation

/// One-time import of SecureWispr's data and settings into Wiska.
public enum LegacyMigration {
    public static let legacySuite = "com.zeta.SecureWispr"
    public static let legacyFolder = "SecureWispr"
    public static let settingsKeys = [
        "engine", "languageMode", "primaryLanguage", "toggleLanguage",
        "lastDetectedLanguage", "cleanupLevel", "historyRetention",
    ]
    static let doneKey = "migratedFromSecureWispr"
    private static let log = Log.logger("Migration")

    public struct Outcome: Equatable {
        public var movedData: Bool
        public var copiedKeys: [String]
    }

    @discardableResult
    public static func run(applicationSupport: URL = URL.applicationSupportDirectory,
                           defaults: UserDefaults = .standard,
                           legacyDefaults: UserDefaults? = UserDefaults(suiteName: legacySuite)) -> Outcome {
        guard !defaults.bool(forKey: doneKey) else { return Outcome(movedData: false, copiedKeys: []) }
        defer { defaults.set(true, forKey: doneKey) }

        let old = applicationSupport.appendingPathComponent(legacyFolder, isDirectory: true)
        let new = applicationSupport.appendingPathComponent(AppPaths.name, isDirectory: true)
        let fm = FileManager.default
        var moved = false
        if fm.fileExists(atPath: old.path) {
            if fm.fileExists(atPath: new.path) {
                log.notice("both SecureWispr and Wiska data folders exist; leaving both untouched")
            } else {
                do {
                    try fm.moveItem(at: old, to: new)   // a rename: the 469 MB model isn't copied
                    moved = true
                } catch {
                    log.error("could not move SecureWispr data: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        var copied: [String] = []
        if let legacyDefaults {
            for key in settingsKeys where defaults.object(forKey: key) == nil {
                if let value = legacyDefaults.object(forKey: key) {
                    defaults.set(value, forKey: key)
                    copied.append(key)
                }
            }
        }
        log.info("migration: movedData=\(moved, privacy: .public) copiedKeys=\(copied.count, privacy: .public)")
        return Outcome(movedData: moved, copiedKeys: copied)
    }
}
