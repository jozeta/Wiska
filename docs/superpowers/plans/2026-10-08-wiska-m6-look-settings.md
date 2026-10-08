# M6 Look & Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Notch-wide capsule with a glide-down animation, selectable highlight colour, tabbed Settings, and launch at login.

**Architecture:** `Highlight` presets live in `Core` and are stored by `SettingsStore`. `NotchLayout` sizes a fixed panel to the notch; `HUDView` animates an internal `reveal` value instead of the panel resizing. The Settings scene becomes a `TabView` with one file per tab in `Wiska/Settings/`. Launch at login wraps `SMAppService.mainApp`.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit (`NSPanel`), ServiceManagement, Swift Testing, SwiftPM `WiskaKit`.

**Spec:** `docs/superpowers/specs/2026-10-08-wiska-m6-look-settings-design.md`

## Global Constraints

- Capsule width = notch width (`auxRight.minX − auxLeft.maxX`); no-notch screens use the built-in notch width, fallback 331 pt; content height 44 pt; 16 pt total side inset for content.
- Show: spring (response 0.28, dampingFraction 0.85). Hide: easeIn 0.2 s, then order out only if nothing happened since.
- Presets and hex stops exactly as spec §3; default `.aurora`; key `highlight`.
- Unchanged colours: menu-bar icon, app icon, `AuroraTheme.danger`, text colours.
- Tabs and order: General, Speech, Languages, Cleanup, Dictionary, History, Appearance.
- Launch at login state comes from `SMAppService.mainApp.status`, never UserDefaults.
- Package tests: `cd WiskaKit && swift test`. App build (repo root): `xcodebuild -project Wiska.xcodeproj -scheme Wiska -allowProvisioningUpdates -derivedDataPath build -quiet build`. The Xcode project uses synchronized folders: new files under `Wiska/` are included automatically.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. A long HUD message (e.g. "Parakeet is selected but not ready…") at notch width → truncates with "…" inside the capsule, never widens it (Task 3, `.lineLimit(1)` + `.truncationMode(.tail)`; verified in manual step).
2. Hide immediately followed by show (language flash right after a dictation) → the shape reverses from where it is, never snaps closed or orders out (Task 3, generation token in `hide()` completion).
3. A screen without a notch (external display) → capsule hangs under the menu bar at the reference width, square top corners (Task 2 `plainScreenUsesTheReferenceWidth`).
4. Launch at login when macOS requires approval → note with a button to Login Items; the checkbox shows the real status (Task 5 `LoginItem.refresh()` on appear).
5. Highlight changed while the capsule is visible → recolours live without re-showing (Task 4, `hud.highlight` set from `applyHighlight()` on change).

---

## File Structure

| File | Responsibility |
|---|---|
| `WiskaKit/Sources/Core/Highlight.swift` (create) | `Highlight` presets and hex stops |
| `WiskaKit/Sources/Preferences/SettingsStore.swift` (modify) | `highlight` setting |
| `WiskaKit/Sources/HUD/NotchLayout.swift` (modify) | notch-wide placement, reference width |
| `WiskaKit/Sources/HUD/HUDReveal.swift` (create; replaces `HUDTransition.swift`) | reveal maths |
| `WiskaKit/Sources/HUD/HUDView.swift`, `HUDContent.swift`, `HUDPanelController.swift`, `WaveformView.swift`, `AuroraTheme.swift` (modify) | glide animation, highlight colours |
| `WiskaKit/Sources/HUD/HUDPreview.swift` (create) | public animated preview capsule for Settings |
| `Wiska/AppModel.swift`, `Wiska/HistoryView.swift`, `Wiska/OnboardingView.swift`, `Wiska/WiskaApp.swift` (modify) | highlight wiring |
| `Wiska/Settings/*.swift` (create), `Wiska/SettingsView.swift` (move into `Wiska/Settings/`) | tabs |
| `Wiska/LoginItem.swift` (create) | `SMAppService` wrapper |

---

### Task 1: Highlight presets and setting

**Files:**
- Create: `WiskaKit/Sources/Core/Highlight.swift`
- Modify: `WiskaKit/Sources/Preferences/SettingsStore.swift`
- Test: `WiskaKit/Tests/CoreTests/HighlightTests.swift` (create), `WiskaKit/Tests/PreferencesTests/SettingsStoreTests.swift`

**Interfaces:**
- Produces: `public enum Highlight: String, Sendable, CaseIterable, Codable { aurora, ocean, sunset, rose, lime, amber, mono }` with `displayName: String`, `start: UInt32`, `end: UInt32`; `SettingsStore.highlight: Highlight`.

- [ ] **Step 1: Failing tests**

```swift
// WiskaKit/Tests/CoreTests/HighlightTests.swift
import Testing
@testable import Core

struct HighlightTests {
    @Test func auroraIsTheCurrentLook() {
        #expect(Highlight.aurora.start == 0x3EE6C1)
        #expect(Highlight.aurora.end == 0x8B6CFF)
    }

    @Test func everyPresetIsAGradient() {
        for preset in Highlight.allCases { #expect(preset.start != preset.end, "\(preset)") }
        #expect(Highlight.allCases.count == 7)
    }

    @Test func rawValuesRoundTrip() {
        for preset in Highlight.allCases { #expect(Highlight(rawValue: preset.rawValue) == preset) }
    }
}
```

Append to `SettingsStoreTests`:

```swift
    @Test func highlightDefaultsToAuroraAndPersists() {
        let store = SettingsStore(defaults: defaults)
        #expect(store.highlight == .aurora)
        store.highlight = .sunset
        #expect(SettingsStore(defaults: defaults).highlight == .sunset)
    }
```

- [ ] **Step 2: Run** `cd WiskaKit && swift test --filter "HighlightTests|SettingsStoreTests"` → build error, `Highlight` not found.

- [ ] **Step 3: Implement**

```swift
// WiskaKit/Sources/Core/Highlight.swift
/// The accent used by the notch capsule and the app's gradients: two sRGB stops.
public enum Highlight: String, Sendable, CaseIterable, Codable {
    case aurora, ocean, sunset, rose, lime, amber, mono

    public var displayName: String {
        switch self {
        case .aurora: "Aurora"
        case .ocean: "Ocean"
        case .sunset: "Sunset"
        case .rose: "Rose"
        case .lime: "Lime"
        case .amber: "Amber"
        case .mono: "Mono"
        }
    }

    public var start: UInt32 {
        switch self {
        case .aurora: 0x3EE6C1
        case .ocean: 0x4FD8FF
        case .sunset: 0xFFB347
        case .rose: 0xFF7EB6
        case .lime: 0xC6F25B
        case .amber: 0xFFD25E
        case .mono: 0xF2F4F7
        }
    }

    public var end: UInt32 {
        switch self {
        case .aurora: 0x8B6CFF
        case .ocean: 0x3D6BFF
        case .sunset: 0xFF5E8A
        case .rose: 0xA86BFF
        case .lime: 0x2FD9A6
        case .amber: 0xFF8A3D
        case .mono: 0x8A93A3
        }
    }
}
```

In `SettingsStore`: key `static let highlight = "highlight"`; property
`public var highlight: Highlight { didSet { defaults.set(highlight.rawValue, forKey: Key.highlight) } }`;
in `init`: `highlight = Self.read(defaults, Key.highlight, Highlight.aurora)`.

- [ ] **Step 4: Run** the same filter → PASS.
- [ ] **Step 5: Commit** `feat(core): highlight colour presets and setting`.

---

### Task 2: Notch-wide placement and reveal maths

**Files:**
- Modify: `WiskaKit/Sources/HUD/NotchLayout.swift`
- Create: `WiskaKit/Sources/HUD/HUDReveal.swift`; Delete: `WiskaKit/Sources/HUD/HUDTransition.swift`, `WiskaKit/Tests/HUDTests/HUDTransitionTests.swift`
- Test: `WiskaKit/Tests/HUDTests/NotchLayoutTests.swift` (rewrite), `WiskaKit/Tests/HUDTests/HUDRevealTests.swift` (create)

**Interfaces:**
- Produces: `NotchLayout.fallbackWidth = 331`; `NotchLayout.notchWidth(_ screen: Screen) -> CGFloat?`; `NotchLayout.placement(on: Screen, referenceWidth: CGFloat, contentHeight: CGFloat) -> Placement`; `HUDReveal.visibleHeight(insetTop:contentHeight:reveal:) -> CGFloat`, `HUDReveal.contentOffset(reveal:) -> CGFloat`. `HUDTransition` is gone.

- [ ] **Step 1: Failing tests** — replace the three tests in `NotchLayoutTests` (keep the `macBook` / `external` fixtures):

```swift
    @Test func notchedScreenIsExactlyAsWideAsTheNotch() {
        let p = NotchLayout.placement(on: macBook, referenceWidth: 331, contentHeight: 44)
        #expect(p.hasNotch)
        #expect(p.frame == CGRect(x: 1186.5, y: 1756 - 101, width: 331, height: 101))
        #expect(p.contentInsetTop == 57)
    }

    @Test func notchWidthIsMeasuredFromTheScreen() {
        #expect(NotchLayout.notchWidth(macBook) == 331)
        #expect(NotchLayout.notchWidth(external) == nil)
    }

    @Test func plainScreenUsesTheReferenceWidth() {
        let p = NotchLayout.placement(on: external, referenceWidth: 331, contentHeight: 44)
        #expect(!p.hasNotch)
        #expect(p.frame == CGRect(x: 2704 + (1920 - 331) / 2, y: 1055 - 44, width: 331, height: 44))
        #expect(p.contentInsetTop == 0)
    }

    @Test func fallbackWidthMatchesTheMacBookNotch() {
        #expect(NotchLayout.fallbackWidth == 331)
    }
```

```swift
// WiskaKit/Tests/HUDTests/HUDRevealTests.swift
import CoreGraphics
import Testing
@testable import HUD

struct HUDRevealTests {
    @Test func shapeGrowsDownOutOfTheNotch() {
        #expect(HUDReveal.visibleHeight(insetTop: 57, contentHeight: 44, reveal: 0) == 57)
        #expect(HUDReveal.visibleHeight(insetTop: 57, contentHeight: 44, reveal: 0.5) == 79)
        #expect(HUDReveal.visibleHeight(insetTop: 57, contentHeight: 44, reveal: 1) == 101)
    }

    @Test func contentSlidesDownAsItArrives() {
        #expect(HUDReveal.contentOffset(reveal: 0) == -6)
        #expect(HUDReveal.contentOffset(reveal: 1) == 0)
    }
}
```

Delete `WiskaKit/Tests/HUDTests/HUDTransitionTests.swift`.

- [ ] **Step 2: Run** `cd WiskaKit && swift test --filter "NotchLayoutTests|HUDRevealTests"` → build error.

- [ ] **Step 3: Implement**

`NotchLayout` — replace `notchPadding` and `placement(on:content:)`:

```swift
    /// The MacBook notch width, used when no screen reports one.
    public static let fallbackWidth: CGFloat = 331

    public static func notchWidth(_ screen: Screen) -> CGFloat? {
        guard screen.safeTop > 0, let left = screen.auxLeft, let right = screen.auxRight,
              right.minX > left.maxX else { return nil }
        return right.minX - left.maxX
    }

    /// Exactly the notch on notched screens; elsewhere the same width, hanging from under the menu bar.
    public static func placement(on screen: Screen, referenceWidth: CGFloat, contentHeight: CGFloat) -> Placement {
        if let width = notchWidth(screen), let left = screen.auxLeft {
            let height = screen.safeTop + contentHeight
            return Placement(frame: CGRect(x: left.maxX, y: screen.frame.maxY - height, width: width, height: height),
                             contentInsetTop: screen.safeTop, hasNotch: true)
        }
        let frame = CGRect(x: screen.frame.midX - referenceWidth / 2, y: screen.visibleFrame.maxY - contentHeight,
                           width: referenceWidth, height: contentHeight)
        return Placement(frame: frame, contentInsetTop: 0, hasNotch: false)
    }
```

Remove `menuBarGap` (the capsule now touches the menu bar).

```swift
// WiskaKit/Sources/HUD/HUDReveal.swift
import CoreGraphics

/// The glide: `reveal` goes 0 (tucked into the notch) → 1 (fully down).
enum HUDReveal {
    static let slide: CGFloat = 6

    static func visibleHeight(insetTop: CGFloat, contentHeight: CGFloat, reveal: CGFloat) -> CGFloat {
        insetTop + reveal * contentHeight
    }

    static func contentOffset(reveal: CGFloat) -> CGFloat {
        (reveal - 1) * slide
    }
}
```

Delete `WiskaKit/Sources/HUD/HUDTransition.swift`. `HUDPanelController` will not compile until Task 3; make the minimum edit now so the package builds: replace its `NotchLayout.placement(on:..., content: Self.contentSize)` call with `NotchLayout.placement(on: ..., referenceWidth: NotchLayout.fallbackWidth, contentHeight: Self.contentSize.height)` and replace `HUDTransition.expandStart(...)`/`collapsedFrame(...)` uses with `placement.frame` (Task 3 rewrites both functions).

- [ ] **Step 4: Run** the filter → PASS; `cd WiskaKit && swift build` → OK.
- [ ] **Step 5: Commit** `feat(hud): capsule exactly as wide as the notch; reveal maths`.

---

### Task 3: Glide animation and highlight colours in the HUD

**Files:**
- Modify: `WiskaKit/Sources/HUD/HUDContent.swift`, `HUDView.swift`, `HUDPanelController.swift`, `WaveformView.swift`, `AuroraTheme.swift`
- Create: `WiskaKit/Sources/HUD/HUDPreview.swift`

**Interfaces:**
- Consumes: `Highlight` (Task 1); `NotchLayout.placement(on:referenceWidth:contentHeight:)`, `notchWidth`, `HUDReveal` (Task 2).
- Produces: `HUDPanelController.highlight: Highlight` (public, settable, live); `AuroraTheme.start(_:)`, `end(_:)`, `gradient(_:) -> LinearGradient`; `public struct HUDPreview: View { public init(highlight: Highlight) }`.

- [ ] **Step 1: Theme helpers** — in `AuroraTheme.swift` (add `import Core`):

```swift
    public static func start(_ highlight: Highlight) -> Color { Color(hex: highlight.start) }
    public static func end(_ highlight: Highlight) -> Color { Color(hex: highlight.end) }
    public static func gradient(_ highlight: Highlight) -> LinearGradient {
        LinearGradient(colors: [start(highlight), end(highlight)], startPoint: .leading, endPoint: .trailing)
    }
```

Keep `teal`, `violet`, `gradient` (Aurora) for existing callers until Task 4 removes their use.

- [ ] **Step 2: Model** — `HUDModel` gains:

```swift
    var highlight: Highlight = .aurora
    /// 0 = tucked into the notch, 1 = fully down. Animated by the panel controller.
    var reveal: CGFloat = 0
```

- [ ] **Step 3: Waveform** — `WaveformView` takes `let highlight: Highlight` and colours bar `index` by interpolating `highlight.start` → `highlight.end`:

```swift
    private func color(at index: Int) -> Color {
        let t = Double(index) / Double(Self.barCount - 1)
        func channel(_ shift: UInt32) -> Double {
            let a = Double((highlight.start >> shift) & 0xFF), b = Double((highlight.end >> shift) & 0xFF)
            return (a + (b - a) * t) / 255
        }
        return Color(.sRGB, red: channel(16), green: channel(8), blue: channel(0))
    }
```

- [ ] **Step 4: View** — `HUDView`: fixed size, the black shape and the content are clipped to the revealed height; content fades and slides:

```swift
struct HUDView: View {
    let model: HUDModel
    static let contentHeight: CGFloat = 44

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 18,
                                           bottomTrailingRadius: 18, topTrailingRadius: 0)
        let visible = HUDReveal.visibleHeight(insetTop: model.insetTop, contentHeight: Self.contentHeight,
                                              reveal: model.reveal)
        VStack(spacing: 0) {
            Color.clear.frame(height: model.insetTop)       // the notch itself
            content
                .lineLimit(1).truncationMode(.tail)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .frame(height: Self.contentHeight)
                .opacity(model.reveal)
                .offset(y: HUDReveal.contentOffset(reveal: model.reveal))
        }
        .background(alignment: .top) { shape.fill(Color.black).frame(height: visible) }
        .mask(alignment: .top) { shape.frame(height: visible) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(AuroraTheme.textPrimary)
    }
```

In `content`, use the highlight: badge `.foregroundStyle(AuroraTheme.start(model.highlight))`, its background `AuroraTheme.start(model.highlight).opacity(0.13)`, `WaveformView(levels: levels, highlight: model.highlight)`, spinner `.tint(AuroraTheme.start(model.highlight))`. `.message` and `.error` unchanged otherwise.

- [ ] **Step 5: Controller** — rewrite `show`/`expand`/`collapse` in `HUDPanelController`:

```swift
    static let contentSize = CGSize(width: NotchLayout.fallbackWidth, height: HUDView.contentHeight)
    private var requested: HUDContent = .hidden

    public var highlight: Highlight {
        get { model.highlight }
        set { model.highlight = newValue }
    }

    public func show(_ content: HUDContent) {
        guard content != requested else { return }
        requested = content
        generation += 1
        guard content != .hidden else { return hide() }
        if !panel.isVisible { place() }
        withAnimation(.easeInOut(duration: 0.12)) { model.content = content }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { model.reveal = 1 }
    }

    private func place() {
        guard let screen = activeScreen() else { return }
        let placement = NotchLayout.placement(on: Self.layoutScreen(screen), referenceWidth: Self.referenceWidth,
                                              contentHeight: HUDView.contentHeight)
        model.insetTop = placement.contentInsetTop
        model.hasNotch = placement.hasNotch
        model.reveal = 0
        panel.setFrame(placement.frame, display: false)
        panel.orderFrontRegardless()
    }

    private func hide() {
        let token = generation
        withAnimation(.easeIn(duration: 0.2)) {
            model.reveal = 0
        } completion: { [weak self] in
            guard let self, self.generation == token else { return }   // shown again meanwhile
            self.model.content = .hidden
            self.panel.orderOut(nil)
        }
    }

    /// The built-in notch width, so capsules on other screens match it.
    private static var referenceWidth: CGFloat {
        NSScreen.screens.lazy.compactMap { NotchLayout.notchWidth(layoutScreen($0)) }.first ?? NotchLayout.fallbackWidth
    }

    private static func layoutScreen(_ screen: NSScreen) -> NotchLayout.Screen {
        NotchLayout.Screen(frame: screen.frame, visibleFrame: screen.visibleFrame, safeTop: screen.safeAreaInsets.top,
                           auxLeft: screen.auxiliaryTopLeftArea, auxRight: screen.auxiliaryTopRightArea)
    }
```

Remove `placement`, `animation`, the old `expand`/`collapse`, and the `NSAnimationContext` code. The `model.content` guard used for "same content" moves to `requested`.

- [ ] **Step 6: Preview** — `HUDPreview.swift`:

```swift
import Core
import SwiftUI

/// The capsule as it looks while listening, with a moving sample waveform — for Settings ▸ Appearance.
public struct HUDPreview: View {
    let highlight: Highlight
    public init(highlight: Highlight) { self.highlight = highlight }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let levels = (0..<WaveformView.barCount).map { i in
                Float(0.25 + 0.75 * abs(sin(t * 3 + Double(i) * 0.45)))
            }
            HStack(spacing: 10) {
                Text("AUTO")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .foregroundStyle(AuroraTheme.start(highlight))
                    .background(AuroraTheme.start(highlight).opacity(0.13), in: RoundedRectangle(cornerRadius: 4))
                WaveformView(levels: levels, highlight: highlight)
            }
            .frame(width: NotchLayout.fallbackWidth, height: HUDView.contentHeight)
            .background(Color.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18))
        }
    }
}
```

- [ ] **Step 7: Build and test** — `cd WiskaKit && swift test --filter HUD` → PASS; app build → exit 0 (AppModel unchanged so far).
- [ ] **Step 8: Commit** `feat(hud): glide-down capsule and highlight colours`.

---

### Task 4: Highlight across the app

**Files:**
- Modify: `Wiska/AppModel.swift`, `Wiska/WiskaApp.swift`, `Wiska/HistoryView.swift`, `Wiska/OnboardingView.swift`, `WiskaKit/Sources/HUD/AuroraTheme.swift`

**Interfaces:**
- Consumes: `SettingsStore.highlight` (Task 1), `HUDPanelController.highlight`, `AuroraTheme.start/end/gradient(_:)` (Task 3).
- Produces: `AppModel.applyHighlight()`; `HistoryView(store:highlight:)`.

- [ ] **Step 1:** `AppModel`: add

```swift
    /// Pushes the chosen colour to the capsule; called at launch and when Settings changes it.
    func applyHighlight() {
        hud.highlight = settings.highlight
    }
```

and call it at the end of `init`.

- [ ] **Step 2:** `HistoryView` gains `let highlight: Highlight` (passed to `StatsHeader`): tiles use `AuroraTheme.gradient(highlight)`; the language bar uses `AuroraTheme.start(highlight)` for Swedish and `AuroraTheme.end(highlight)` for English. `WiskaApp`: `HistoryView(store: model.history, highlight: model.settings.highlight)`.
- [ ] **Step 3:** `OnboardingView`: title `AuroraTheme.gradient(model.settings.highlight)`, done check mark `AuroraTheme.start(model.settings.highlight)`.
- [ ] **Step 4:** Remove `AuroraTheme.teal`, `violet` and the parameterless `gradient` once `grep -rn "AuroraTheme\.\(teal\|violet\|gradient\b\)" Wiska WiskaKit/Sources` is empty.
- [ ] **Step 5:** App build → exit 0; `cd WiskaKit && swift test` → all pass.
- [ ] **Step 6: Commit** `feat(app): highlight colour in History, Onboarding and the capsule`.

---

### Task 5: Tabbed Settings, Appearance and launch at login

**Files:**
- Create: `Wiska/LoginItem.swift`, `Wiska/Settings/SettingsView.swift`, `GeneralTab.swift`, `SpeechTab.swift`, `LanguagesTab.swift`, `CleanupTab.swift`, `DictionaryTab.swift`, `HistoryTab.swift`, `AppearanceTab.swift`
- Delete: `Wiska/SettingsView.swift` (its content is split into the tabs)

**Interfaces:**
- Consumes: everything in `AppModel` the old `SettingsView` used; `HUDPreview` (Task 3); `Highlight`, `applyHighlight()` (Tasks 1, 4).
- Produces: `@MainActor @Observable final class LoginItem { var isEnabled: Bool; var needsApproval: Bool; var error: String?; func refresh(); func setEnabled(_:) }`.

- [ ] **Step 1: LoginItem**

```swift
// Wiska/LoginItem.swift
import Foundation
import Observation
import ServiceManagement

/// Launch at login via the system's login items. The truth lives in macOS, not in UserDefaults.
@MainActor @Observable
final class LoginItem {
    private(set) var isEnabled = false
    private(set) var needsApproval = false
    private(set) var error: String?

    /// The login item points at this copy of the app; moving it later needs re-enabling.
    var isOutsideApplications: Bool { !Bundle.main.bundlePath.hasPrefix("/Applications/") }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
    }

    func openLoginItemsSettings() { SMAppService.openSystemSettingsLoginItems() }
}
```

- [ ] **Step 2: Tabs** — `Wiska/Settings/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralTab(model: model) }
            Tab("Speech", systemImage: "waveform") { SpeechTab(model: model) }
            Tab("Languages", systemImage: "globe") { LanguagesTab(model: model) }
            Tab("Cleanup", systemImage: "sparkles") { CleanupTab(model: model) }
            Tab("Dictionary", systemImage: "character.book.closed") { DictionaryTab(store: model.dictionaryStore) }
            Tab("History", systemImage: "clock") { HistoryTab(model: model) }
            Tab("Appearance", systemImage: "paintpalette") { AppearanceTab(model: model) }
        }
        .frame(width: 520)
    }
}
```

Each tab is a `Form { … }.formStyle(.grouped)` holding exactly the old section(s) listed in spec §4, moved verbatim from the old `SettingsView.swift` (Speech: the engine section + `ParakeetCard`, which moves into `SpeechTab.swift`; Languages: the language section; Cleanup: the cleanup section; Dictionary: `DictionarySection`'s body, renamed `DictionaryTab`; History: the history section with `@Environment(\.openWindow)`). Each tab ends with `.fixedSize(horizontal: false, vertical: true)` so the window fits its content.

- [ ] **Step 3: General tab**

```swift
// Wiska/Settings/GeneralTab.swift
import SwiftUI

struct GeneralTab: View {
    let model: AppModel
    @State private var login = LoginItem()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch Wiska at login", isOn: Binding(get: { login.isEnabled },
                                                               set: { login.setEnabled($0) }))
                if login.needsApproval {
                    HStack {
                        Text("Approve Wiska in System Settings → Login Items.").font(.caption)
                        Button("Open Login Items") { login.openLoginItemsSettings() }
                    }
                }
                if let error = login.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                if login.isOutsideApplications {
                    Text("Starts this copy of Wiska. After moving Wiska to Applications, turn this off and on again.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Push-to-talk") {
                LabeledContent("Dictate", value: "Hold fn, speak, release")
            }
            Section("Permissions") {
                LabeledContent("Status", value: model.missingPermissions.isEmpty ? "All granted" : "Setup needed")
                Button("Open Setup…") { OnboardingWindow.open(openWindow) }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { login.refresh() }
    }
}
```

- [ ] **Step 4: Appearance tab**

```swift
// Wiska/Settings/AppearanceTab.swift
import Core
import HUD
import SwiftUI

struct AppearanceTab: View {
    let model: AppModel

    var body: some View {
        Form {
            Section("Highlight colour") {
                HStack { Spacer(); HUDPreview(highlight: model.settings.highlight); Spacer() }
                    .padding(.vertical, 8)
                HStack(spacing: 12) {
                    ForEach(Highlight.allCases, id: \.self) { preset in
                        Button {
                            model.settings.highlight = preset
                            model.applyHighlight()
                        } label: {
                            VStack(spacing: 4) {
                                Circle().fill(AuroraTheme.gradient(preset)).frame(width: 28, height: 28)
                                    .overlay(Circle().stroke(Color.primary, lineWidth: preset == model.settings.highlight ? 2 : 0)
                                        .padding(-3))
                                Text(preset.displayName).font(.caption2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Colours the notch capsule, the waveform and Wiska's accents.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}
```

- [ ] **Step 5: Build and suite** — delete the old `Wiska/SettingsView.swift`; app build → exit 0; `cd WiskaKit && swift test` → all pass.
- [ ] **Step 6: Commit** `feat(settings): tabbed Settings, Appearance with colour presets, launch at login`.

---

### Task 6: Acceptance

- [ ] **Step 1:** Full suite and app build; quit Wiska; `open build/Build/Products/Debug/Wiska.app`.
- [ ] **Step 2: User checklist**
  1. Hold fn: the capsule glides down out of the notch and is no wider than the notch; release: it glides back up. A dictation right after another (language flash) doesn't snap.
  2. Trigger a long message (dictate into a password field: "Can't type here") — stays inside the capsule.
  3. Settings → Appearance: click each swatch; the preview and the next real dictation use it; History tiles and Onboarding use it.
  4. Every Settings tab fits without scrolling; all old settings are present in their tab.
  5. General → Launch at login on; log out and in; Wiska is running.
