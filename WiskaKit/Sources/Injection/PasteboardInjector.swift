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
    /// The user's clipboard, waiting to be put back after the last paste.
    private var pending: (snapshot: PasteboardSnapshot, changeCount: Int, task: Task<Void, Never>)?

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

    /// Returns as soon as ⌘V is sent; the user's clipboard comes back a moment later, so the
    /// dictation is done the instant its text is in.
    public func inject(_ text: String) async throws {
        guard !isSecureInputActive() else { throw InjectionError.secureInputActive }

        // A paste right after the last one: put the user's clipboard back first, or this paste
        // would save the last dictation as "the user's clipboard".
        restorePending()
        AXSelectionReader.clipboardWillBeWrittenByWiska(pasteboard)
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
        let task = Task { [self, restoreDelay] in
            try? await Task.sleep(for: restoreDelay)
            guard !Task.isCancelled else { return }
            restorePending()
        }
        pending = (snapshot, ourChangeCount, task)
    }

    /// Puts the user's clipboard back now, unless something else has written it since.
    func restorePending() {
        guard let pending else { return }
        self.pending = nil
        pending.task.cancel()
        if pasteboard.changeCount == pending.changeCount {
            pending.snapshot.restore(to: pasteboard)
        } else {
            Self.log.info("clipboard changed during paste; not restoring")
        }
    }
}
