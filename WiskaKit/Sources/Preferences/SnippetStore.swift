import Core
import Foundation
import Observation

/// The user's snippets, saved as JSON next to the dictionary.
@MainActor @Observable
public final class SnippetStore {
    private static let log = Log.logger("Preferences")

    public nonisolated static var defaultURL: URL { AppPaths.file("snippets.json") }

    public private(set) var snippets: [Snippet]
    @ObservationIgnored private let url: URL

    public init(url: URL = SnippetStore.defaultURL) {
        self.url = url
        snippets = Self.load(from: url)
    }

    public func add(_ snippet: Snippet) {
        snippets.append(snippet)
        save()
    }

    public func update(_ snippet: Snippet) {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        snippets[index] = snippet
        save()
    }

    /// Removes a snippet that still has neither a name nor text (an abandoned "Add Snippet").
    public func removeIfEmpty(id: UUID) {
        guard let snippet = snippets.first(where: { $0.id == id }),
              snippet.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              snippet.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        remove(id: id)
    }

    public func remove(id: UUID) {
        snippets.removeAll { $0.id == id }
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(snippets).write(to: url, options: .atomic)
        } catch {
            Self.log.error("could not save snippets: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from url: URL) -> [Snippet] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try JSONDecoder().decode([Snippet].self, from: data)
        } catch {
            // Never overwrite a file we couldn't read: keep it aside for the user.
            let aside = url.deletingLastPathComponent().appendingPathComponent("snippets.corrupt.json")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: url, to: aside)
            log.error("snippets.json unreadable; moved to snippets.corrupt.json")
            return []
        }
    }
}
