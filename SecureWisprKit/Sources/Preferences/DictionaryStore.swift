import Core
import Foundation
import Observation

/// The personal dictionary, stored as readable JSON so it can be backed up or edited by hand.
@MainActor @Observable
public final class DictionaryStore {
    private static let log = Log.logger("Preferences")

    public nonisolated static var defaultURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("SecureWispr/dictionary.json")
    }

    public private(set) var dictionary: PersonalDictionary
    @ObservationIgnored private let url: URL

    public init(url: URL = DictionaryStore.defaultURL) {
        self.url = url
        dictionary = Self.load(from: url)
    }

    public func addWord(_ word: String) {
        update { $0.words.append(word) }
    }

    public func removeWords(at offsets: IndexSet) {
        update { dictionary in
            for index in offsets.sorted(by: >) where dictionary.words.indices.contains(index) {
                dictionary.words.remove(at: index)
            }
        }
    }

    public func addReplacement(heard: String, written: String) {
        update { $0.replacements.append(Replacement(heard: heard, written: written)) }
    }

    public func removeReplacement(id: UUID) {
        update { $0.replacements.removeAll { $0.id == id } }
    }

    private func update(_ change: (inout PersonalDictionary) -> Void) {
        var next = dictionary
        change(&next)
        dictionary = next.normalized()
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(dictionary).write(to: url, options: .atomic)
        } catch {
            Self.log.error("could not save dictionary: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from url: URL) -> PersonalDictionary {
        guard let data = try? Data(contentsOf: url) else { return PersonalDictionary() }
        do {
            return try JSONDecoder().decode(PersonalDictionary.self, from: data).normalized()
        } catch {
            // Never overwrite a file we couldn't read: keep it aside for the user.
            let aside = url.deletingLastPathComponent().appendingPathComponent("dictionary.corrupt.json")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: url, to: aside)
            log.error("dictionary.json unreadable; moved to dictionary.corrupt.json")
            return PersonalDictionary()
        }
    }
}
