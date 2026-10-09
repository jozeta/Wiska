import AppKit
import ApplicationServices
import Core

/// The selected text in the frontmost app: asked through Accessibility (no clipboard), else
/// copied with ⌘C for apps that don't expose it (Electron, browsers), with the clipboard restored.
@MainActor
public final class AXSelectionReader: SelectionReader {
    private let pasteboard: NSPasteboard
    private let accessibilitySelection: @MainActor () -> String?
    private let accessibilityContext: @MainActor () -> (text: String, cursor: Int)?
    private let sendCopy: @MainActor () throws -> Void
    private let copyTimeout: Duration

    public init(pasteboard: NSPasteboard = .general,
                accessibilitySelection: @escaping @MainActor () -> String? = AXSelectionReader.focusedSelection,
                accessibilityContext: @escaping @MainActor () -> (text: String, cursor: Int)? = AXSelectionReader.focusedTextAroundCursor,
                sendCopy: @escaping @MainActor () throws -> Void = { try CGEventKeySender().sendCopy() },
                copyTimeout: Duration = .milliseconds(300)) {
        self.pasteboard = pasteboard
        self.accessibilitySelection = accessibilitySelection
        self.accessibilityContext = accessibilityContext
        self.sendCopy = sendCopy
        self.copyTimeout = copyTimeout
    }

    public func selectedText() async -> String? {
        if let text = Self.nonBlank(accessibilitySelection()) { return text }
        let snapshot = PasteboardSnapshot.capture(pasteboard)
        let before = pasteboard.changeCount
        do { try sendCopy() } catch { return nil }
        let deadline = ContinuousClock.now + copyTimeout
        while pasteboard.changeCount == before, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard pasteboard.changeCount != before else {
            // Nothing copied (yet): leave the clipboard alone, but undo a copy that lands late.
            undoLateCopy(after: before, restoring: snapshot)
            return nil
        }
        let text = Self.isLineCopy(pasteboard) ? nil : Self.nonBlank(pasteboard.string(forType: .string))
        snapshot.restore(to: pasteboard)
        return text
    }

    /// Watches a little longer: a busy app may finish ⌘C after we stopped waiting, which would
    /// replace the user's clipboard with the selection.
    private func undoLateCopy(after changeCount: Int, restoring snapshot: PasteboardSnapshot) {
        let pasteboard = pasteboard
        Self.lateCopyWatches[pasteboard.name]?.cancel()
        Self.lateCopyWatches[pasteboard.name] = Task { @MainActor in
            let end = ContinuousClock.now + Self.lateCopyWindow
            while ContinuousClock.now < end {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                if pasteboard.changeCount != changeCount {
                    snapshot.restore(to: pasteboard)
                    return
                }
            }
        }
    }

    static let lateCopyWindow: Duration = .seconds(1)
    private static var lateCopyWatches: [NSPasteboard.Name: Task<Void, Never>] = [:]

    /// Wiska is about to write this clipboard itself (a paste or a copy): that's not a late ⌘C.
    public static func clipboardWillBeWrittenByWiska(_ pasteboard: NSPasteboard) {
        lateCopyWatches.removeValue(forKey: pasteboard.name)?.cancel()
    }

    /// VS Code (and Cursor) copy the whole line when nothing is selected, and say so inside Chromium's
    /// custom clipboard data (UTF-16): `"isFromEmptySelection":true`.
    static func isLineCopy(_ pasteboard: NSPasteboard) -> Bool {
        guard let data = pasteboard.data(forType: .init("org.chromium.web-custom-data")),
              let text = String(data: data, encoding: .utf16LittleEndian) else { return false }
        return text.contains(#""isFromEmptySelection":true"#)
    }

    private static func nonBlank(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    /// The focused element's selected text, via Accessibility; nil when the app doesn't say.
    public static func focusedSelection() -> String? {
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString,
                                            &focused) == .success, let focused,
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString,
                                            &selected) == .success else { return nil }
        return selected as? String
    }

    /// Read on-device for the model only; never stored or logged.
    public func surroundingText() async -> String? {
        guard let found = accessibilityContext() else { return nil }
        let window = CursorContext.window(text: found.text, cursor: found.cursor)
        return window.isEmpty ? nil : window
    }

    /// The focused element's text and cursor (start of its selected range), via Accessibility.
    public static func focusedTextAroundCursor() -> (text: String, cursor: Int)? {
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString,
                                            &focused) == .success, let focused,
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String else { return nil }
        var rangeValue: CFTypeRef?
        var range = CFRange(location: text.utf16.count, length: 0)   // no range reported: the end
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
           let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID() {
            AXValueGetValue(rangeValue as! AXValue, .cfRange, &range)
        }
        return (text, range.location)
    }
}
