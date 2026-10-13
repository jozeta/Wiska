import Core
import Foundation
import Observation
import SwiftData

public struct HistoryItem: Identifiable, Sendable, Equatable {
    public let id: PersistentIdentifier
    public let record: DictationRecord
}

/// Private, local dictation history. Failures are logged and never affect dictation.
@MainActor @Observable
public final class HistoryStore {
    private static let log = Log.logger("History")

    public nonisolated static var defaultURL: URL {
        AppPaths.file("History.store")
    }

    /// Bumped on every change so SwiftUI views re-query.
    public private(set) var revision = 0
    @ObservationIgnored private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    public init(inMemory: Bool = false, url: URL = HistoryStore.defaultURL) throws {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        } else {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            configuration = ModelConfiguration(url: url)
        }
        container = try ModelContainer(for: HistoryEntry.self, configurations: configuration)
    }

    public func add(_ record: DictationRecord, retention: HistoryRetention) {
        guard retention != .off else { return }
        context.insert(HistoryEntry(record))
        save()
    }

    public func items(matching query: String) -> [HistoryItem] {
        let descriptor = FetchDescriptor<HistoryEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let entries = (try? context.fetch(descriptor)) ?? []
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return entries
            .filter { trimmed.isEmpty
                || $0.finalText.localizedCaseInsensitiveContains(trimmed)
                || $0.rawText.localizedCaseInsensitiveContains(trimmed) }
            .map { HistoryItem(id: $0.persistentModelID, record: $0.record) }
    }

    /// Reads only the stats window, so it stays fast with Forever retention.
    /// The same 7 calendar days as the Stats tab's "7 days" (today and the 6 days before).
    public func stats(now: Date = Date(), calendar: Calendar = .current) -> DictationStats {
        let start = HistoryPeriod.week.start(now: now, calendar: calendar)
            ?? now.addingTimeInterval(-DictationStats.window)
        let descriptor = FetchDescriptor<HistoryEntry>(predicate: #Predicate { $0.date >= start })
        let records = ((try? context.fetch(descriptor)) ?? []).map(\.record)
        return DictationStats.compute(records, now: now, window: now.timeIntervalSince(start))
    }

    /// The newest dictation, read alone (for "Paste last dictation").
    public func latest() -> DictationRecord? {
        var descriptor = FetchDescriptor<HistoryEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.record
    }

    public func delete(_ id: PersistentIdentifier) {
        // Fetched, not `model(for:)`: that returns a stale object for an entry retention
        // already deleted, and touching it crashes.
        var descriptor = FetchDescriptor<HistoryEntry>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        guard let entry = try? context.fetch(descriptor).first else { return }
        context.delete(entry)
        save()
    }

    public func deleteAll() {
        do { try context.delete(model: HistoryEntry.self) } catch {
            Self.log.error("could not clear history: \(error.localizedDescription, privacy: .public)")
        }
        save()
    }

    /// Deletes entries the retention setting no longer allows (all of them for `.off`).
    public func apply(retention: HistoryRetention, now: Date = Date()) {
        guard let cutoff = retention.cutoff(now: now) else { return }
        if retention == .off { return deleteAll() }
        let descriptor = FetchDescriptor<HistoryEntry>(predicate: #Predicate { $0.date < cutoff })
        let expired = (try? context.fetch(descriptor)) ?? []
        guard !expired.isEmpty else { return }   // runs every minute: don't redraw for nothing
        for entry in expired { context.delete(entry) }
        save()
    }

    private func save() {
        do { try context.save() } catch {
            Self.log.error("could not save history: \(error.localizedDescription, privacy: .public)")
        }
        revision += 1
    }
}
