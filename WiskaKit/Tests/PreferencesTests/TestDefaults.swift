import Foundation

/// Removes a throwaway UserDefaults suite completely: its values, and the empty plist
/// that cfprefsd otherwise leaves in ~/Library/Preferences.
func discardTestDefaults(_ suite: String) {
    UserDefaults.standard.removePersistentDomain(forName: suite)
    let file = URL.libraryDirectory.appendingPathComponent("Preferences/\(suite).plist")
    try? FileManager.default.removeItem(at: file)
}
