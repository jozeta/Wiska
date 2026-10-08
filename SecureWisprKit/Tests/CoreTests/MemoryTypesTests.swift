import Foundation
import Testing
@testable import Core

struct MemoryTypesTests {
    @Test func normalizedTrimsDropsEmptiesAndDedupes() {
        let dictionary = PersonalDictionary(
            words: ["  Kvarnholmen ", "kvarnholmen", "", "Jozeta"],
            replacements: [Replacement(heard: " secure whisper ", written: "SecureWispr"),
                           Replacement(heard: "", written: "x"),
                           Replacement(heard: "Secure Whisper", written: "Other")]
        ).normalized()
        #expect(dictionary.words == ["Kvarnholmen", "Jozeta"])
        #expect(dictionary.replacements.map(\.heard) == ["secure whisper"])
    }

    @Test func retentionCutoffs() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(HistoryRetention.forever.cutoff(now: now) == nil)
        #expect(HistoryRetention.week.cutoff(now: now) == now.addingTimeInterval(-7 * 86_400))
        #expect(HistoryRetention.off.cutoff(now: now) == now)
    }
}
