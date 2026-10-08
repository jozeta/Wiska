import Core
import SwiftUI

/// Wiska's Midnight Aurora palette; the accent comes from the chosen `Highlight`.
public enum AuroraTheme {
    public static let ink = Color(hex: 0x0E1116)
    public static let panel = Color(hex: 0x151A22)
    public static let danger = Color(hex: 0xFF9A9A)
    public static let textPrimary = Color(hex: 0xE8ECF2)
    public static let textSecondary = Color(hex: 0x8A93A3)

    public static func start(_ highlight: Highlight) -> Color { Color(hex: highlight.start) }
    public static func end(_ highlight: Highlight) -> Color { Color(hex: highlight.end) }
    public static func gradient(_ highlight: Highlight) -> LinearGradient {
        LinearGradient(colors: [start(highlight), end(highlight)], startPoint: .leading, endPoint: .trailing)
    }

}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
