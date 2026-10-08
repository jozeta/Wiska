import Core
import Foundation

/// M1 cleaner: no model, just trims. M3 replaces it with a Foundation Models cleaner.
public struct PassthroughCleaner: TextCleaner {
    public init() {}

    public func clean(_ text: String, context: DictationContext) async throws -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
