import Foundation

/// A throwaway UserDefaults suite name. An absolute path makes cfprefsd keep the plist at
/// that path, in the temp folder, instead of ~/Library/Preferences, where it writes the
/// file back asynchronously even after the domain is removed and the file deleted.
func testDefaultsSuite(_ prefix: String) -> String {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)").path
}

/// Removes a throwaway suite made by `testDefaultsSuite`: its values and its plist.
func discardTestDefaults(_ suite: String) {
    UserDefaults.standard.removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(atPath: suite + ".plist")
}
