import AppKit
import Core

/// Puts the text on the clipboard and leaves it there (Settings → "Copy to clipboard only").
@MainActor
public final class ClipboardCopier: TextInjector {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public func inject(_ text: String) async throws {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

/// Inserts or copies, following the setting at the moment the text is ready.
@MainActor
public final class SwitchingInjector: TextInjector {
    private let mode: @MainActor () -> OutputMode
    private let insert: any TextInjector
    private let copy: any TextInjector

    public init(mode: @escaping @MainActor () -> OutputMode, insert: any TextInjector, copy: any TextInjector) {
        self.mode = mode
        self.insert = insert
        self.copy = copy
    }

    public func inject(_ text: String) async throws {
        switch mode() {
        case .insert: try await insert.inject(text)
        case .clipboard: try await copy.inject(text)
        }
    }
}
