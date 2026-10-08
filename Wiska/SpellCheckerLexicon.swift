import AppKit
import SwiftUI

/// "Is this a real Swedish or English word?" backed by the system spell checker, cached.
/// Keeps the dictionary corrector from turning "hann" into "Hanna" (review C1).
@MainActor
final class SpellCheckerLexicon {
    private let checker = NSSpellChecker.shared
    private var cache: [String: Bool] = [:]
    private let languages = ["sv", "en"]

    func isKnown(_ word: String) -> Bool {
        if let hit = cache[word] { return hit }
        let known = languages.contains { language in
            checker.checkSpelling(of: word, startingAt: 0, language: language, wrap: false,
                                  inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
        }
        if cache.count > 5_000 { cache.removeAll() }
        cache[word] = known
        return known
    }
}

/// Opens the History window in front of the app being dictated into (an accessory app
/// isn't active, so a plain openWindow lands behind — same issue Settings had).
@MainActor
enum HistoryWindow {
    static let id = "history"
    static let title = "Dictation History"

    static func open(_ openWindow: OpenWindowAction) {
        NSApp.activate()
        openWindow(id: id)
        DispatchQueue.main.async {
            NSApp.windows.first { $0.title == title }?.orderFrontRegardless()
        }
    }
}

/// The first-run checklist window, opened in front like Settings and History.
@MainActor
enum OnboardingWindow {
    static let id = "onboarding"
    static let title = "Welcome to Wiska"

    static func open(_ openWindow: OpenWindowAction) {
        NSApp.activate()
        openWindow(id: id)
        DispatchQueue.main.async {
            NSApp.windows.first { $0.title == title }?.orderFrontRegardless()
        }
    }
}
