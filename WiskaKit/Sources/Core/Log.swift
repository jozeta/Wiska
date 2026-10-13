import Foundation
import os

/// Wiska's unified-log entries (Console.app, or `log show --predicate 'subsystem == "Wiska"' --last 1h`).
/// Lines meant for diagnosing a problem later are `notice` or above: macOS keeps only those on disk.
/// Dictated text, selections and the text around the cursor are never logged in the clear.
public enum Log {
    public static let subsystem = "Wiska"

    public static func logger(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }

    /// An error's type and case ("GenerationError.exceededContextWindowSize"), or a Foundation
    /// error's domain and code: enough to diagnose, and safe to log in the clear. Never the
    /// description, which may quote what was dictated.
    public static func summary(_ error: Error) -> String {
        let mirror = Mirror(reflecting: error)
        let type = String(describing: Swift.type(of: error))
        if mirror.displayStyle == .enum {
            // A case with a value is the mirror's only child, labelled with the case's name.
            if let name = mirror.children.first?.label { return "\(type).\(name)" }
            if !(Swift.type(of: error) is CustomStringConvertible.Type) { return "\(type).\(String(describing: error))" }
        }
        // Foundation and system errors: the domain and code say it all.
        if let urlError = error as? URLError { return "\(NSURLErrorDomain) \(urlError.code.rawValue)" }
        if Swift.type(of: error) is NSError.Type {
            let bridged = error as NSError
            return "\(bridged.domain) \(bridged.code)"
        }
        return type
    }

    /// Words in a text, for logging its size instead of its content.
    public static func words(_ text: String?) -> Int {
        text?.split(whereSeparator: \.isWhitespace).count ?? 0
    }

    /// A duration as whole milliseconds, for log lines.
    public static func ms(_ duration: Duration) -> String {
        duration.formatted(.units(allowed: [.milliseconds]))
    }
}
