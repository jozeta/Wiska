/// What kind of app the text goes into; decides the writing style and formatting.
public enum AppCategory: String, Sendable, CaseIterable, Codable {
    case personal, work, email, code, other

    public var displayName: String {
        switch self {
        case .personal: "Personal messages"
        case .work: "Work chat"
        case .email: "Email"
        case .code: "Code"
        case .other: "Other"
        }
    }

    /// The style used until the user picks one. Code has none: it always gets exactly what was said.
    public var defaultStyle: WritingStyle? {
        switch self {
        case .personal, .work: .casual
        case .email, .other: .formal
        case .code: nil
        }
    }
}

/// How finished the cleaned text looks.
public enum WritingStyle: String, Sendable, CaseIterable, Codable {
    case formal, casual, veryCasual

    public var displayName: String {
        switch self {
        case .formal: "Formal"
        case .casual: "Casual"
        case .veryCasual: "Very casual"
        }
    }

    public var example: String {
        switch self {
        case .formal: "Hi Anna, I'll be there at 3."
        case .casual: "Hi Anna, I'll be there at 3"
        case .veryCasual: "hi anna i'll be there at 3"
        }
    }
}

/// Which category an app belongs to: the user's choice, then the built-in list, otherwise Other.
public enum AppCatalog {
    static let builtIn: [String: AppCategory] = [
        "com.apple.MobileSMS": .personal, "net.whatsapp.WhatsApp": .personal,
        "org.whispersystems.signal-desktop": .personal, "ru.keepcoder.Telegram": .personal,
        "com.hnc.Discord": .personal,
        "com.tinyspeck.slackmacgap": .work, "com.microsoft.teams2": .work, "com.microsoft.teams": .work,
        "us.zoom.xos": .work,
        "com.apple.mail": .email, "com.microsoft.Outlook": .email, "com.readdle.smartemail-Mac": .email,
        "it.bloop.airmail2": .email,
        "com.apple.Terminal": .code, "com.googlecode.iterm2": .code, "com.apple.dt.Xcode": .code,
        "com.microsoft.VSCode": .code, "com.todesktop.230313mzl4w4u92": .code, "dev.zed.Zed": .code,
        "dev.warp.Warp-Stable": .code, "com.mitchellh.ghostty": .code,
    ]

    public static func category(for bundleID: String?, overrides: [String: AppCategory] = [:]) -> AppCategory {
        guard let bundleID else { return .other }
        return overrides[bundleID] ?? builtIn[bundleID] ?? .other
    }
}
