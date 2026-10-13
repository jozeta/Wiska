import Foundation
import Testing
@testable import Core

struct DiagnosticsTests {
    /// What's pasted into a bug report: the lines, never a private value or a debug line.
    @Test func collectsNoticesWithoutPrivateValues() async throws {
        let log = Log.logger("DiagnosticsTest")
        let secret = "my secret dictation"
        log.notice("visible line \(42) with \(secret, privacy: .private)")
        log.debug("debug line \(secret, privacy: .public)")
        let text = try await runBlocking { try Diagnostics.collect(header: "Wiska test") }
        #expect(text.hasPrefix("Wiska test"))
        #expect(text.contains("[DiagnosticsTest] visible line 42"))
        #expect(!text.contains(secret))
        #expect(!text.contains("debug line"))
    }
}
