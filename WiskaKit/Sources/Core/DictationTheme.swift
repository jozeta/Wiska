/// How dictation is shown on screen. Raw values are stored in settings: never rename them.
public enum DictationTheme: String, Sendable, CaseIterable, Codable {
    /// The original capsule that drops down from the notch.
    case notchDropdown
    /// A bar the height of the notch, growing out of both its sides.
    case expandedNotch
    /// A floating, glowing orb that reacts to the voice.
    case orb
    /// A paperclip assistant with a speech bubble.
    case clippy

    public var displayName: String {
        switch self {
        case .notchDropdown: "Notch Dropdown"
        case .expandedNotch: "Expanded Notch"
        case .orb: "Magical Orb"
        case .clippy: "Clippy"
        }
    }

    public var summary: String {
        switch self {
        case .notchDropdown: "The capsule that drops down from the notch, with the live preview."
        case .expandedNotch: "Grows out of both sides of the notch: the state on the left, the waveform on the right."
        case .orb: "A floating, glowing orb that reacts to your voice. Drag it anywhere."
        case .clippy: "A paperclip assistant that listens along and shows the live preview in a bubble."
        }
    }

    /// Floating themes stay on screen while idle and can be dragged.
    public var isFloating: Bool { self == .orb || self == .clippy }
}

/// Where a floating theme's window sits among other windows.
public enum FloatingWindowBehavior: String, Sendable, CaseIterable, Codable {
    /// Above normal app windows.
    case alwaysOnTop
    /// On the desktop: above the wallpaper and icons, below every app window.
    case desktop

    public var displayName: String {
        switch self {
        case .alwaysOnTop: "Always on top"
        case .desktop: "Desktop"
        }
    }
}
