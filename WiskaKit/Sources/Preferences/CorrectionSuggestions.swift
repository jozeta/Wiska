import Core
import Foundation
import Observation

/// Words the user corrected after a dictation, waiting in the Dictionary tab to be added or
/// dismissed. Only the word pairs are kept (corrections.json), never the text around them.
@MainActor @Observable
public final class CorrectionSuggestions {
    private static let log = Log.logger("Preferences")

    public struct Suggestion: Codable, Equatable, Identifiable, Sendable {
        public let correction: Correction
        /// How often the user made this correction.
        public var count: Int
        public var lastSeen: Date
        public var id: Correction { correction }
    }

    private struct Stored: Codable {
        var pending: [Suggestion] = []
        var dismissed: [Correction] = []
    }

    public nonisolated static var defaultURL: URL { AppPaths.file("corrections.json") }

    public private(set) var pending: [Suggestion]
    @ObservationIgnored private var dismissed: Set<Correction>
    @ObservationIgnored private let url: URL

    public init(url: URL = CorrectionSuggestions.defaultURL) {
        self.url = url
        let stored = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) } ?? Stored()
        pending = stored.pending
        dismissed = Set(stored.dismissed)
    }

    /// Records a correction; true when it's new (worth telling the user about).
    @discardableResult
    public func note(_ correction: Correction, now: Date = Date()) -> Bool {
        guard !dismissed.contains(correction) else { return false }
        if let index = pending.firstIndex(where: { $0.correction == correction }) {
            pending[index].count += 1
            pending[index].lastSeen = now
            save()
            return false
        }
        pending.insert(Suggestion(correction: correction, count: 1, lastSeen: now), at: 0)
        save()
        return true
    }

    /// Added to the dictionary: no longer a suggestion.
    public func accept(_ correction: Correction) {
        pending.removeAll { $0.correction == correction }
        save()
    }

    /// Not wanted: never suggested again.
    public func dismiss(_ correction: Correction) {
        pending.removeAll { $0.correction == correction }
        dismissed.insert(correction)
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(Stored(pending: pending, dismissed: dismissed.sorted { $0.heard < $1.heard }))
                .write(to: url, options: .atomic)
        } catch {
            Self.log.error("could not save corrections: \(Log.summary(error), privacy: .public)")
        }
    }
}
