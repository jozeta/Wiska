import AppKit
import ApplicationServices
import Core

/// The selected text in the frontmost app: asked through Accessibility (no clipboard), else
/// copied with ⌘C for apps that don't expose it (Electron, browsers), with the clipboard restored.
@MainActor
public final class AXSelectionReader: SelectionReader {
    private let pasteboard: NSPasteboard
    private let accessibilitySelection: @MainActor () -> String?
    private let sendCopy: @MainActor () throws -> Void
    private let copyTimeout: Duration

    public init(pasteboard: NSPasteboard = .general,
                accessibilitySelection: @escaping @MainActor () -> String? = AXSelectionReader.focusedSelection,
                sendCopy: @escaping @MainActor () throws -> Void = { try CGEventKeySender().sendCopy() },
                copyTimeout: Duration = .milliseconds(300)) {
        self.pasteboard = pasteboard
        self.accessibilitySelection = accessibilitySelection
        self.sendCopy = sendCopy
        self.copyTimeout = copyTimeout
    }

    public func selectedText() async -> String? {
        if let text = Self.nonBlank(accessibilitySelection()) { return text }
        let snapshot = PasteboardSnapshot.capture(pasteboard)
        let before = pasteboard.changeCount
        defer { snapshot.restore(to: pasteboard) }
        do { try sendCopy() } catch { return nil }
        let deadline = ContinuousClock.now + copyTimeout
        while pasteboard.changeCount == before, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard pasteboard.changeCount != before else { return nil }
        return Self.nonBlank(pasteboard.string(forType: .string))
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
}
