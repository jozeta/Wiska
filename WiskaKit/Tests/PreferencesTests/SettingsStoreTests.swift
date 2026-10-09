import Core
import Foundation
import Testing
@testable import Preferences

@MainActor
final class SettingsStoreTests {
    let suite = testDefaultsSuite("WiskaTests")
    lazy var defaults = UserDefaults(suiteName: suite)!

    // Throwaway stores live in the temp folder; remove them after every test.
    deinit { discardTestDefaults(suite) }

    @Test func defaultsMatchTheSpec() {
        let store = SettingsStore(defaults: defaults)
        #expect(store.engine == .apple)
        #expect(store.languageMode == .autoDetect)
        #expect(store.primaryLanguage == .english)
        #expect(store.toggleLanguage == .english)
        #expect(store.lastDetectedLanguage == .english)
    }

    @Test func valuesPersistAcrossInstances() {
        let store = SettingsStore(defaults: defaults)
        store.engine = .parakeet
        store.languageMode = .perLanguageHotkeys
        store.primaryLanguage = .swedish
        store.toggleLanguage = .swedish
        store.lastDetectedLanguage = .swedish

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.engine == .parakeet)
        #expect(reloaded.languageMode == .perLanguageHotkeys)
        #expect(reloaded.primaryLanguage == .swedish)
        #expect(reloaded.toggleLanguage == .swedish)
        #expect(reloaded.lastDetectedLanguage == .swedish)
    }

    @Test func corruptValuesFallBackToDefaults() {
        defaults.set("banana", forKey: "engine")
        defaults.set(42, forKey: "languageMode")
        let store = SettingsStore(defaults: defaults)
        #expect(store.engine == .apple)
        #expect(store.languageMode == .autoDetect)
    }

    @Test func cleanupLevelDefaultsToPolishedAndPersists() {
        let store = SettingsStore(defaults: defaults)
        #expect(store.cleanupLevel == .polished)
        store.cleanupLevel = .light
        #expect(SettingsStore(defaults: defaults).cleanupLevel == .light)
    }

    @Test func historyRetentionDefaultsToAWeekAndPersists() {
        let store = SettingsStore(defaults: defaults)
        #expect(store.historyRetention == .week)
        store.historyRetention = .month
        #expect(SettingsStore(defaults: defaults).historyRetention == .month)
    }

    @Test func onboardingFlagsDefaultFalseAndPersist() {
        let store = SettingsStore(defaults: defaults)
        #expect(!store.onboardingCompleted && !store.fnKeyConfirmed && !store.firstDictationDone)
        store.onboardingCompleted = true
        store.fnKeyConfirmed = true
        store.firstDictationDone = true
        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.onboardingCompleted && reloaded.fnKeyConfirmed && reloaded.firstDictationDone)
    }

    @Test func highlightDefaultsToAuroraAndPersists() {
        let store = SettingsStore(defaults: defaults)
        #expect(store.highlight == .aurora)
        store.highlight = .sunset
        #expect(SettingsStore(defaults: defaults).highlight == .sunset)
    }

    @Test func perLanguageEnginesStartFromTheCurrentEngine() {
        defaults.set("parakeet", forKey: "engine")
        let store = SettingsStore(defaults: defaults)
        store.engineMode = .perLanguage
        #expect(Language.allCases.allSatisfy { store.engine(for: $0) == .parakeet })
    }

    @Test func existingEnglishAndSwedishEnginesCarryOver() {
        defaults.set("perLanguage", forKey: "engineMode")
        defaults.set("parakeet", forKey: "englishEngine")
        defaults.set("apple", forKey: "swedishEngine")
        let store = SettingsStore(defaults: defaults)
        #expect(store.engine(for: .english) == .parakeet)
        #expect(store.engine(for: .swedish) == .apple)
    }

    @Test func engineForLanguageFollowsTheMode() {
        let store = SettingsStore(defaults: defaults)
        store.engine = .parakeet
        store.setEngine(.apple, for: .german)
        #expect(store.engine(for: .german) == .parakeet)   // same for all
        store.engineMode = .perLanguage
        #expect(store.engine(for: .german) == .apple)
    }

    @Test func engineSettingsPersist() {
        let store = SettingsStore(defaults: defaults)
        store.engineMode = .perLanguage
        store.setEngine(.parakeet, for: .dutch)
        #expect(SettingsStore(defaults: defaults).engine(for: .dutch) == .parakeet)
    }

    @Test func perLanguageEnginesAreSavedWhenThatModeIsChosen() {
        let store = SettingsStore(defaults: defaults)
        store.engine = .parakeet
        store.engineMode = .perLanguage
        store.engine = .apple
        #expect(SettingsStore(defaults: defaults).engine(for: .italian) == .parakeet)
    }

    @Test func usesParakeetWhenAnyLanguageDoes() {
        let store = SettingsStore(defaults: defaults)
        #expect(!store.usesParakeet)
        store.engineMode = .perLanguage
        store.setEngine(.parakeet, for: .swedish)
        #expect(store.usesParakeet)
    }

    @Test func englishAndSwedishAreTickedByDefault() {
        #expect(SettingsStore(defaults: defaults).enabledLanguages == [.english, .swedish])
    }

    @Test func tickedLanguagesPersistInDisplayOrder() {
        let store = SettingsStore(defaults: defaults)
        store.enabledLanguages = [.dutch, .english, .german]
        #expect(SettingsStore(defaults: defaults).enabledLanguages == [.english, .german, .dutch])
    }

    @Test func theLastLanguageCannotBeUnticked() {
        let store = SettingsStore(defaults: defaults)
        store.enabledLanguages = []
        #expect(store.enabledLanguages == [.english, .swedish])
    }

    @Test func atMostFiveLanguagesCanBeTicked() {
        let store = SettingsStore(defaults: defaults)
        store.enabledLanguages = [.english, .swedish, .german, .french, .spanish, .italian]
        #expect(store.enabledLanguages == [.english, .swedish])
        store.enabledLanguages = [.english, .swedish, .german, .french, .spanish]
        #expect(store.enabledLanguages.count == 5)
    }

    @Test func untickedLanguagesFallBackToTheFirstTicked() {
        let store = SettingsStore(defaults: defaults)
        store.toggleLanguage = .swedish
        store.primaryLanguage = .swedish
        store.enabledLanguages = [.german, .french]
        #expect(store.toggleLanguage == .german)
        #expect(store.primaryLanguage == .german)
        #expect(store.secondaryLanguage == .french)
    }

    @Test func secondaryLanguageIsStoredAndNeverThePrimary() {
        let store = SettingsStore(defaults: defaults)
        store.enabledLanguages = [.english, .swedish, .german]
        store.secondaryLanguage = .german
        #expect(SettingsStore(defaults: defaults).secondaryLanguage == .german)
        store.primaryLanguage = .german
        #expect(store.secondaryLanguage == .english)
    }

    @Test func usesParakeetOnlyCountsTickedLanguages() {
        let store = SettingsStore(defaults: defaults)
        store.engineMode = .perLanguage
        store.setEngine(.parakeet, for: .italian)
        #expect(!store.usesParakeet)
        store.enabledLanguages = [.english, .italian]
        #expect(store.usesParakeet)
    }

    @Test func handsFreeAndPreviewDefaultsAndPersist() {
        let store = SettingsStore(defaults: defaults)
        #expect(store.handsFreeSilence == 30)
        #expect(store.livePreview)
        store.handsFreeSilence = 0
        store.livePreview = false
        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.handsFreeSilence == 0)
        #expect(!reloaded.livePreview)
    }

    @Test func stylesDefaultPerCategoryAndPersist() {
        let store = SettingsStore(defaults: defaults)
        #expect(store.style(for: .personal) == .casual)
        #expect(store.style(for: .email) == .formal)
        store.setStyle(.veryCasual, for: .personal)
        #expect(SettingsStore(defaults: defaults).style(for: .personal) == .veryCasual)
        #expect(SettingsStore(defaults: defaults).style(for: .work) == .casual)
    }

    @Test func appCategoriesPersistAndReset() {
        let store = SettingsStore(defaults: defaults)
        store.setCategory(.work, for: "com.apple.mail")
        #expect(SettingsStore(defaults: defaults).appCategories == ["com.apple.mail": .work])
        store.setCategory(nil, for: "com.apple.mail")
        #expect(SettingsStore(defaults: defaults).appCategories.isEmpty)
        store.setCategory(.code, for: "a")
        store.resetAppCategories()
        #expect(SettingsStore(defaults: defaults).appCategories.isEmpty)
    }

    @Test func recentAppsAreMostRecentFirstAndCapped() {
        let store = SettingsStore(defaults: defaults)
        for index in 0..<15 { store.noteRecentApp("app\(index)") }
        store.noteRecentApp("app3")
        let reloaded = SettingsStore(defaults: defaults).recentApps
        #expect(reloaded.count == SettingsStore.maxRecentApps)
        #expect(reloaded.first == "app3")
        #expect(reloaded.filter { $0 == "app3" }.count == 1)
    }

    @Test func corruptStyleValuesFallBack() {
        defaults.set(["personal": "shouting", "nonsense": "formal"], forKey: "categoryStyles")
        #expect(SettingsStore(defaults: defaults).style(for: .personal) == .casual)
    }

    @Test func languageModelAndGrammarDefaultsAndPersist() {
        let store = SettingsStore(defaults: defaults)
        #expect(store.languageModel == .apple)
        #expect(store.fixGrammar)
        store.languageModel = .gemma
        store.fixGrammar = false
        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.languageModel == .gemma)
        #expect(!reloaded.fixGrammar)
        #expect(LanguageModelChoice.gemma.displayName == "Gemma 4 E4B (on this Mac)")
        #expect(LanguageModelChoice.apple.displayName == "Apple Intelligence")
    }

    @Test func useKBWhisperDefaultsOffAndPersists() {
        let store = SettingsStore(defaults: defaults)
        #expect(!store.useKBWhisper)
        store.useKBWhisper = true
        #expect(SettingsStore(defaults: defaults).useKBWhisper)
    }

    @Test func outputModeDefaultsToInsertAndPersists() {
        let store = SettingsStore(defaults: defaults)
        #expect(store.outputMode == .insert)
        store.outputMode = .clipboard
        #expect(SettingsStore(defaults: defaults).outputMode == .clipboard)
    }

    @Test func modelUpdateSettings() {
        let store = SettingsStore(defaults: defaults)
        #expect(store.modelUpdateInterval == 7)
        #expect(store.lastModelUpdateCheck == nil)
        let date = Date(timeIntervalSince1970: 1_000_000)
        store.modelUpdateInterval = 30
        store.lastModelUpdateCheck = date
        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.modelUpdateInterval == 30)
        #expect(reloaded.lastModelUpdateCheck == date)
        #expect(SettingsStore.modelUpdateIntervals == [0, 1, 7, 30])
    }
}
