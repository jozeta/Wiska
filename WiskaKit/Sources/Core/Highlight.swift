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
