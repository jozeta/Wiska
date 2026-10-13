/// The global shortcut that pastes the last dictation again. Raw values are stored in settings.
public enum PasteLastShortcut: String, Sendable, CaseIterable, Codable {
    case off
    case controlOptionV
    case optionCommandV
    case controlOptionCommandV

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .controlOptionV: "⌃⌥V"
        case .optionCommandV: "⌥⌘V"
        case .controlOptionCommandV: "⌃⌥⌘V"
        }
    }

    /// The key: V (Carbon's kVK_ANSI_V).
    public var keyCode: UInt32? { self == .off ? nil : 9 }

    /// Carbon modifier flags (cmdKey 256, optionKey 2048, controlKey 4096).
    public var carbonModifiers: UInt32 {
        switch self {
        case .off: 0
        case .controlOptionV: 4096 | 2048
        case .optionCommandV: 2048 | 256
        case .controlOptionCommandV: 4096 | 2048 | 256
        }
    }
}
