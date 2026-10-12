import Core
import Foundation
import Testing
@testable import Preferences

@MainActor
final class DictationThemeSettingsTests {
    let suite = testDefaultsSuite("WiskaThemeTests")
    lazy var defaults = UserDefaults(suiteName: suite)!

    deinit { discardTestDefaults(suite) }

    @Test func existingInstallsKeepTheNotchDropdown() {
        let store = SettingsStore(defaults: defaults)
        #expect(store.dictationTheme == .notchDropdown)
        #expect(store.orbSize == SettingsStore.defaultOrbSize)
        #expect(store.orbHighlight == nil)
        #expect(store.orbWindowBehavior == .alwaysOnTop)
        #expect(store.clippyWindowBehavior == .alwaysOnTop)
        #expect(store.orbOrigin == nil)
        #expect(store.clippyOrigin == nil)
    }

    @Test func everyThemeAndItsSettingsPersist() {
        for theme in DictationTheme.allCases {
            SettingsStore(defaults: defaults).dictationTheme = theme
            #expect(SettingsStore(defaults: defaults).dictationTheme == theme)
        }
        let store = SettingsStore(defaults: defaults)
        store.orbSize = 200
        store.orbHighlight = .sunset
        store.orbWindowBehavior = .desktop
        store.clippyWindowBehavior = .desktop
        store.orbOrigin = CGPoint(x: 120.5, y: -300)
        store.clippyOrigin = CGPoint(x: 2000, y: 40)

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.orbSize == 200)
        #expect(reloaded.orbHighlight == .sunset)
        #expect(reloaded.orbWindowBehavior == .desktop)
        #expect(reloaded.clippyWindowBehavior == .desktop)
        #expect(reloaded.orbOrigin == CGPoint(x: 120.5, y: -300))
        #expect(reloaded.clippyOrigin == CGPoint(x: 2000, y: 40))

        reloaded.orbHighlight = nil
        reloaded.orbOrigin = nil
        #expect(SettingsStore(defaults: defaults).orbHighlight == nil)
        #expect(SettingsStore(defaults: defaults).orbOrigin == nil)
    }

    @Test func invalidValuesFallBackSafely() {
        defaults.set("hologram", forKey: "dictationTheme")
        defaults.set("ceiling", forKey: "orbWindowBehavior")
        defaults.set("plaid", forKey: "orbHighlight")
        defaults.set(9_999.0, forKey: "orbSize")
        defaults.set([1.0], forKey: "orbOrigin")
        defaults.set("x", forKey: "clippyOrigin")
        let store = SettingsStore(defaults: defaults)
        #expect(store.dictationTheme == .notchDropdown)
        #expect(store.orbWindowBehavior == .alwaysOnTop)
        #expect(store.orbHighlight == nil)
        #expect(store.orbSize == SettingsStore.orbSizeRange.upperBound)
        #expect(store.orbOrigin == nil)
        #expect(store.clippyOrigin == nil)
    }

    @Test func orbSizeIsKeptInRange() {
        let store = SettingsStore(defaults: defaults)
        store.orbSize = 10
        #expect(store.orbSize == SettingsStore.orbSizeRange.lowerBound)
        store.orbSize = .nan
        #expect(store.orbSize == SettingsStore.defaultOrbSize)
    }
}
