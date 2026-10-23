import ApplicationServices
import Core

/// After a paste, watches the text field for a minute so a word the user fixes can be offered
/// for the dictionary. Reads through Accessibility, keeps the text in memory only, and stops
/// early when focus moves to another field or another dictation starts.
@MainActor
public final class CorrectionWatcher {
    /// The focused field (any value that tells fields apart) and its text, or nil.
    public typealias Reader = @MainActor () -> (AnyHashable, String)?

    private let read: Reader
    private let settle: Duration
    private let interval: Duration
    private let duration: Duration
    private var task: Task<Void, Never>?
    private var before: String?
    private var latest: String?
    private var report: ((String, String) -> Void)?

    public init(read: @escaping Reader = CorrectionWatcher.focusedField, settle: Duration = .milliseconds(600),
                interval: Duration = .seconds(2), duration: Duration = .seconds(60)) {
        self.read = read
        self.settle = settle
        self.interval = interval
        self.duration = duration
    }

    /// For tests: a reader returning (Int, String).
    convenience init(read: @escaping @MainActor () -> (Int, String)?, settle: Duration, interval: Duration, duration: Duration) {
        self.init(read: { read().map { (AnyHashable($0.0), $0.1) } }, settle: settle, interval: interval, duration: duration)
    }

    /// Starts watching the focused field; `report(before, after)` runs once when the watch ends.
    public func watch(_ report: @escaping (String, String) -> Void) {
        finish()
        self.report = report
        task = Task { [weak self, settle, interval, duration] in
            try? await Task.sleep(for: settle)   // the paste lands first
            guard let self, !Task.isCancelled, let first = self.read() else { return }
            self.before = first.1
            self.latest = first.1
            let end = ContinuousClock.now + duration
            while ContinuousClock.now < end {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                guard let now = self.read(), now.0 == first.0 else { break }   // focus moved on
                self.latest = now.1
            }
            self.finish()
        }
    }

    /// Ends the watch now (a new dictation, or Wiska quitting) and reports what changed.
    public func finish() {
        task?.cancel()
        task = nil
        if let report, let before, let latest { report(before, latest) }
        report = nil
        before = nil
        latest = nil
    }

    /// The longest field worth comparing; a huge document isn't read every two seconds.
    static let maxCharacters = 20_000

    public static func focusedField() -> (AnyHashable, String)? {
        guard let element = AXSelectionReader.focusedElement(timeout: 0.3) else { return nil }
        var count: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &count) == .success,
           let characters = count as? Int, characters > maxCharacters { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String, text.count <= maxCharacters else { return nil }
        return (AnyHashable(element as CFTypeRef as! NSObject), text)
    }
}
