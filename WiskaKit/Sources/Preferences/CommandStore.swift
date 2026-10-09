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

    /// Where an unreadable commands file was moved this launch (shown in the Commands tab).
    public private(set) var setAsideFile: URL?

    public init(url: URL = CommandStore.defaultURL) {
        self.url = url
        let result = Self.load(from: url)
        setAsideFile = result.setAside
        if let loaded = result.commands {
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

    /// Removes every abandoned command, with one save (closing the Commands tab).
    public func removeEmpty() {
        let kept = commands.filter { !($0.spokenPhrases.isEmpty && $0.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        guard kept.count != commands.count else { return }
        commands = kept
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

    /// nil commands when there's no file yet, or when it was unreadable (then it's set aside,
    /// under its own dated name, so an earlier one is never overwritten).
    private static func load(from url: URL) -> (commands: [SavedCommand]?, setAside: URL?) {
        guard FileManager.default.fileExists(atPath: url.path) else { return (nil, nil) }
        do {
            return (try JSONDecoder().decode([SavedCommand].self, from: Data(contentsOf: url)), nil)
        } catch {
            // Never overwrite a file we couldn't read: keep it aside for the user.
            let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true))
                .replacingOccurrences(of: ":", with: "-")
            // The date for people, a short random suffix so two in the same instant never collide.
            let suffix = UUID().uuidString.prefix(6)
            let aside = url.deletingLastPathComponent().appendingPathComponent("commands.corrupt-\(stamp)-\(suffix).json")
            do {
                try FileManager.default.moveItem(at: url, to: aside)
            } catch {
                log.error("commands.json unreadable and couldn't be moved aside")
                return (nil, nil)
            }
            log.error("commands.json unreadable; moved aside")
            return (nil, aside)
        }
    }
}
