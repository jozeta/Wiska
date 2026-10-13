import Core
import Foundation
import Testing
@testable import Preferences

@MainActor
struct CorrectionSuggestionsTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("corr-\(UUID().uuidString)")
    var url: URL { dir.appendingPathComponent("corrections.json") }
    let wisca = Correction(heard: "Wisca", written: "Wiska")

    @Test func aNotedCorrectionIsSuggestedOnceAndCounted() {
        let store = CorrectionSuggestions(url: url)
        #expect(store.note(wisca))
        #expect(!store.note(wisca))          // already suggested: no new notice
        #expect(store.pending.map(\.correction) == [wisca])
        #expect(store.pending.first?.count == 2)
        #expect(CorrectionSuggestions(url: url).pending.map(\.correction) == [wisca])
    }

    @Test func dismissedCorrectionsStayAway() {
        let store = CorrectionSuggestions(url: url)
        store.note(wisca)
        store.dismiss(wisca)
        #expect(store.pending.isEmpty)
        #expect(!store.note(wisca))
        #expect(CorrectionSuggestions(url: url).pending.isEmpty)
    }

    @Test func acceptingRemovesTheSuggestion() {
        let store = CorrectionSuggestions(url: url)
        store.note(wisca)
        store.accept(wisca)
        #expect(store.pending.isEmpty)
    }
}
