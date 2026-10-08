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

    @Test func perLanguageEnginesStartFromTheCurrentEngine() {
        defaults.set("parakeet", forKey: "engine")
        let store = SettingsStore(defaults: defaults)
        #expect(store.engineMode == .same)
        #expect(store.englishEngine == .parakeet)
        #expect(store.swedishEngine == .parakeet)
    }

    @Test func engineForLanguageFollowsTheMode() {
        let store = SettingsStore(defaults: defaults)
        store.engine = .parakeet
        store.englishEngine = .parakeet
        store.swedishEngine = .apple
        #expect(store.engine(for: .swedish) == .parakeet)   // same for all
        store.engineMode = .perLanguage
        #expect(store.engine(for: .english) == .parakeet)
        #expect(store.engine(for: .swedish) == .apple)
    }

    @Test func usesParakeetWhenAnyLanguageDoes() {
        let store = SettingsStore(defaults: defaults)
        #expect(!store.usesParakeet)
        store.engineMode = .perLanguage
        store.swedishEngine = .parakeet
        #expect(store.usesParakeet)
    }

    @Test func engineSettingsPersist() {
        let store = SettingsStore(defaults: defaults)
        store.engineMode = .perLanguage
        store.englishEngine = .parakeet
        store.swedishEngine = .apple
        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.engineMode == .perLanguage)
        #expect(reloaded.englishEngine == .parakeet)
        #expect(reloaded.swedishEngine == .apple)
    }

    @Test func perLanguageEnginesAreSavedWhenThatModeIsChosen() {
        let store = SettingsStore(defaults: defaults)
        store.engine = .parakeet
        store.engineMode = .perLanguage   // both start as Parakeet and are now saved
        store.engine = .apple             // a later "Same for all" change must not move them
        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.englishEngine == .parakeet)
        #expect(reloaded.swedishEngine == .parakeet)
    }
}
