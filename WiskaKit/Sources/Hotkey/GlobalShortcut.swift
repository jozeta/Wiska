import Carbon.HIToolbox
import Core

/// One system-wide keyboard shortcut (Carbon hot key): works in every app and needs no
/// permission. `action` runs on the main thread each time it's pressed.
@MainActor
public final class GlobalShortcut {
    private static let log = Log.logger("Hotkey")
    private let action: @MainActor () -> Void
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    public init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    /// Replaces the registered shortcut (nil key: none). False when macOS refused it, e.g.
    /// because another app already uses it.
    @discardableResult
    public func register(keyCode: UInt32?, modifiers: UInt32) -> Bool {
        unregister()
        guard let keyCode else { return true }
        if handler == nil, !installHandler() { return false }
        let id = EventHotKeyID(signature: OSType(0x5769_736B), id: 1)   // 'Wisk'
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
        guard status == noErr else {
            Self.log.error("shortcut not registered: OSStatus \(status, privacy: .public)")
            hotKey = nil
            return false
        }
        return true
    }

    public func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    private func installHandler() -> Bool {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { shortcut.action() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else {
            Self.log.error("shortcut handler not installed: OSStatus \(status, privacy: .public)")
            return false
        }
        return true
    }

    isolated deinit {
        unregister()
        if let handler { RemoveEventHandler(handler) }
    }
}
