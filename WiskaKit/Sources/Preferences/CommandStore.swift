import Core
import Foundation
import Observation

/// The user's saved commands, as JSON next to the snippets. Starts with `CommandResolver.defaults`.
@MainActor @Observable
public final class CommandStore {
    private static let log = Log.logger("Preferences")

    public nonisolated static var defaultURL: URL { AppPaths.file("commands.json") }

    public private(set) var commands: [SavedCommand]
    @ObservationIgnored private let url: URL

    public init(url: URL = CommandStore.defaultURL) {
        self.url = url
        if let loaded = Self.load(from: url) {
            commands = loaded
        } else {
            commands = CommandResolver.defaults
            if !FileManager.default.fileExists(atPath: url.path) { save() }
        }
    }

    public func add(_ command: SavedCommand) {
        commands.append(command)
        save()
    }

    public func update(_ command: SavedCommand) {
        guard let index = commands.firstIndex(where: { $0.id == command.id }) else { return }
        commands[index] = command
        save()
    }

    /// Removes a command that still has neither a phrase nor an instruction (an abandoned "Add Command").
    public func removeIfEmpty(id: UUID) {
        guard let command = commands.first(where: { $0.id == id }),
              command.spokenPhrases.isEmpty,
              command.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        remove(id: id)
    }

    public func remove(id: UUID) {
        commands.removeAll { $0.id == id }
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(commands).write(to: url, options: .atomic)
        } catch {
            Self.log.error("could not save commands: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// nil when there's no file yet, or when it was unreadable (then it's set aside).
    private static func load(from url: URL) -> [SavedCommand]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode([SavedCommand].self, from: data)
        } catch {
            // Never overwrite a file we couldn't read: keep it aside for the user.
            let aside = url.deletingLastPathComponent().appendingPathComponent("commands.corrupt.json")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: url, to: aside)
            log.error("commands.json unreadable; moved to commands.corrupt.json")
            return nil
        }
    }
}
