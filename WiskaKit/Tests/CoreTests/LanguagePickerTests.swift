import Foundation
import Testing
@testable import Core

struct LanguagePickerTests {
    private func t(_ text: String, _ language: Language, _ confidence: Double?) -> Transcript {
        Transcript(text: text, locale: language.locale, confidence: confidence, language: language)
    }

    @Test func clearWinnerIsChosen() {
        let picked = LanguagePicker.pick([t("hello", .english, 0.95), t("hallå", .swedish, 0.40)], fallback: .swedish)
        #expect(picked.language == .english)
    }

    @Test func withinMarginUsesFallback() {
        let picked = LanguagePicker.pick([t("hello", .english, 0.80), t("hallå", .swedish, 0.75)], fallback: .swedish)
        #expect(picked.language == .swedish)
    }

    @Test func emptyCandidateIsIgnored() {
        let picked = LanguagePicker.pick([t("", .english, 0.99), t("hej", .swedish, 0.30)], fallback: .english)
        #expect(picked.language == .swedish)
    }

    @Test func nilConfidenceRanksBelowAnyValue() {
        let picked = LanguagePicker.pick([t("hello", .english, nil), t("hej", .swedish, 0.30)], fallback: .english)
        #expect(picked.language == .swedish)
    }

    @Test func allEmptyReturnsAnEmptyTranscript() {
        let picked = LanguagePicker.pick([t("", .english, 0.9), t("", .swedish, 0.9)], fallback: .swedish)
        #expect(picked.text.isEmpty)
    }

    @Test func languageHelpers() {
        #expect(Language.english.other == .swedish)
        #expect(Language.swedish.locale.identifier == "sv_SE")
        #expect(Language.swedish.badge == "SV")
    }
}
