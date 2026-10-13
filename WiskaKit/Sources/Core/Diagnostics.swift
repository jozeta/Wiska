import Foundation
import OSLog

/// Settings → Help → Copy diagnostics: Wiska's log since it started, as text for a bug report.
/// Only notice-level lines and above, which by design never hold what was dictated (private
/// values are redacted by the system as well).
public enum Diagnostics {
    public static func collect(header: String, now: Date = Date()) throws -> String {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store.getEntries(matching: NSPredicate(format: "subsystem == %@", Log.subsystem))
        let time = Date.FormatStyle().year().month().day().hour().minute().second()
        var lines = [header, "Collected \(now.formatted(time))", ""]
        for case let entry as OSLogEntryLog in entries where entry.level.rawValue >= OSLogEntryLog.Level.notice.rawValue {
            let level = entry.level == .error || entry.level == .fault ? " ERROR" : ""
            lines.append("\(entry.date.formatted(time))\(level) [\(entry.category)] \(entry.composedMessage)")
        }
        if lines.count == 3 { lines.append("(nothing logged since Wiska started)") }
        return lines.joined(separator: "\n")
    }
}
