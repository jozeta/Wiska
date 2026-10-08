import AppKit
import Carbon.HIToolbox
import Core

/// Puts text at the cursor by pasting, then puts the user's clipboard back.
@MainActor
public final class PasteboardInjector: TextInjector {
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let log = Log.logger("Injection")

    private let pasteboard: NSPasteboard
    private let keySender: any KeySender
    private let restoreDelay: Duration
    private let isSecureInputActive: @MainActor () -> Bool

    public init(
        pasteboard: NSPasteboard = .general,
        keySender: any KeySender = CGEventKeySender(),
        restoreDelay: Duration = .milliseconds(300),
        isSecureInputActive: @escaping @MainActor () -> Bool = { IsSecureEventInputEnabled() }
    ) {
        self.pasteboard = pasteboard
        self.keySender = keySender
        self.restoreDelay = restoreDelay
        self.isSecureInputActive = isSecureInputActive
    }

    public func inject(_ text: String) async throws {
        guard !isSecureInputActive() else { throw InjectionError.secureInputActive }

        let snapshot = PasteboardSnapshot.capture(pasteboard)
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: Self.transientType)
        item.setData(Data(), forType: Self.concealedType)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        let ourChangeCount = pasteboard.changeCount

        do {
            try keySender.sendPaste()
        } catch {
            snapshot.restore(to: pasteboard)
            throw error
        }

        // The target app reads the pasteboard asynchronously after ⌘V; wait before restoring.
        try? await Task.sleep(for: restoreDelay)
        if pasteboard.changeCount == ourChangeCount {
            snapshot.restore(to: pasteboard)
        } else {
            Self.log.info("clipboard changed during paste; not restoring")
        }
    }
}
