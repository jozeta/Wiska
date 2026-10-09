import Foundation
import Testing
@testable import Core

struct LanguageTests {
    @Test func kbWhisperIsAnEngineButNotAPickerChoice() {
        #expect(SpeechEngine.kbWhisper.displayName == "KB-Whisper")
        #expect(SpeechEngine.kbWhisper.shortName == "KB-Whisper")
        #expect(SpeechEngine.selectable == [.apple, .parakeet])
    }

    @Test func nineLanguagesInDisplayOrder() {
        #expect(Language.allCases.map(\.badge) == ["EN", "SV", "DE", "FR", "ES", "IT", "PT", "DA", "NL"])
        #expect(Language.allCases.map(\.locale.identifier)
                == ["en_US", "sv_SE", "de_DE", "fr_FR", "es_ES", "it_IT", "pt_PT", "da_DK", "nl_NL"])
    }

    @Test func nextCyclesThroughTickedLanguages() {
        let ticked: [Language] = [.english, .german, .danish]
        #expect(Language.english.next(in: ticked) == .german)
        #expect(Language.danish.next(in: ticked) == .english)
        #expect(Language.swedish.next(in: ticked) == .german)   // unticked: the next ticked after it
    }

    @Test func nextWithOneLanguageIsItself() {
        #expect(Language.french.next(in: [.french]) == .french)
    }

    @Test func dictationTranscriberOnlyWhereSpeechTranscriberIsMissing() {
        #expect(Language.allCases.filter(\.usesDictationTranscriber) == [.swedish, .danish, .dutch])
    }
}
