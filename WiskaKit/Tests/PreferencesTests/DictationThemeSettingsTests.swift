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
        #expect(store.clippySize == SettingsStore.defaultClippySize)
        #expect(!store.clippyFollowsPointer)
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
        store.clippySize = 180
        store.clippyFollowsPointer = true
        store.orbWindowBehavior = .desktop
        store.clippyWindowBehavior = .desktop
        store.orbOrigin = CGPoint(x: 120.5, y: -300)
        store.clippyOrigin = CGPoint(x: 2000, y: 40)

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.orbSize == 200)
        #expect(reloaded.clippySize == 180)
        #expect(reloaded.clippyFollowsPointer)
        #expect(reloaded.orbWindowBehavior == .desktop)
        #expect(reloaded.clippyWindowBehavior == .desktop)
        #expect(reloaded.orbOrigin == CGPoint(x: 120.5, y: -300))
        #expect(reloaded.clippyOrigin == CGPoint(x: 2000, y: 40))

        reloaded.orbOrigin = nil
        #expect(SettingsStore(defaults: defaults).orbOrigin == nil)
    }

    @Test func invalidValuesFallBackSafely() {
        defaults.set("hologram", forKey: "dictationTheme")
        defaults.set("ceiling", forKey: "orbWindowBehavior")
        defaults.set(-5.0, forKey: "clippySize")
        defaults.set(9_999.0, forKey: "orbSize")
        defaults.set([1.0], forKey: "orbOrigin")
        defaults.set("x", forKey: "clippyOrigin")
        let store = SettingsStore(defaults: defaults)
        #expect(store.dictationTheme == .notchDropdown)
        #expect(store.orbWindowBehavior == .alwaysOnTop)
        #expect(store.clippySize == SettingsStore.clippySizeRange.lowerBound)
        #expect(store.orbSize == SettingsStore.orbSizeRange.upperBound)
        #expect(store.orbOrigin == nil)
        #expect(store.clippyOrigin == nil)
    }

    /// The orb goes from half the old largest size (120) to double it (480); Clippy keeps 80…240.
    @Test func eachThemeHasItsOwnSizeRange() {
        #expect(SettingsStore.orbSizeRange == 120...480)
        #expect(SettingsStore.clippySizeRange == 80...240)
        #expect(SettingsStore.orbSizeRange.contains(SettingsStore.defaultOrbSize))
        defaults.set(100.0, forKey: "orbSize")                    // saved under the old range
        #expect(SettingsStore(defaults: defaults).orbSize == 120)
        let store = SettingsStore(defaults: defaults)
        store.orbSize = 460
        #expect(SettingsStore(defaults: defaults).orbSize == 460)
    }

    @Test func sizesAreKeptInRange() {
        let store = SettingsStore(defaults: defaults)
        store.orbSize = 10
        #expect(store.orbSize == SettingsStore.orbSizeRange.lowerBound)
        store.orbSize = .nan
        #expect(store.orbSize == SettingsStore.defaultOrbSize)
        store.clippySize = 1_000
        #expect(store.clippySize == SettingsStore.clippySizeRange.upperBound)
        store.clippySize = .infinity
        #expect(store.clippySize == SettingsStore.defaultClippySize)
    }
}
