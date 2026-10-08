import Foundation

/// Where Wiska keeps its data. One place, so a rename never scatters paths again.
public enum AppPaths {
    public static let name = "Wiska"

    public static var supportDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent(name, isDirectory: true)
    }

    public static func file(_ name: String) -> URL {
        supportDirectory.appendingPathComponent(name)
    }
}
