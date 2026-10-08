import Core
import Testing
@testable import Cleanup

@MainActor
struct PassthroughCleanerTests {
    @Test func trimsSurroundingWhitespaceOnly() async throws {
        let cleaned = try await PassthroughCleaner().clean("  hello, um, world \n", context: DictationContext())
        #expect(cleaned == "hello, um, world")
    }
}
