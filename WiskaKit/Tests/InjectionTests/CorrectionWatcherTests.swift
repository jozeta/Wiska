import Core
import Testing
@testable import Injection

@MainActor
struct CorrectionWatcherTests {
    /// Reads a scripted field: (element id, text) per read.
    final class Field {
        var reads: [(Int, String)?]
        init(_ reads: [(Int, String)?]) { self.reads = reads }
        func next() -> (Int, String)? { reads.count > 1 ? reads.removeFirst() : reads.first ?? nil }
    }

    @Test func reportsTheFieldBeforeAndAfterWhenTimeRunsOut() async throws {
        let field = Field([(1, "I tried Wisca."), (1, "I tried Wisca."), (1, "I tried Wiska.")])
        var reported: (String, String)?
        let watcher = CorrectionWatcher(read: { field.next() }, settle: .milliseconds(1),
                                        interval: .milliseconds(5), duration: .milliseconds(60))
        watcher.watch { reported = ($0, $1) }
        try await Task.sleep(for: .milliseconds(200))
        #expect(reported?.0 == "I tried Wisca.")
        #expect(reported?.1 == "I tried Wiska.")
    }

    @Test func movingToAnotherFieldEndsTheWatch() async throws {
        let field = Field([(1, "a Wisca"), (1, "a Wiska"), (2, "elsewhere")])
        var reported: (String, String)?
        let watcher = CorrectionWatcher(read: { field.next() }, settle: .milliseconds(1),
                                        interval: .milliseconds(5), duration: .seconds(10))
        watcher.watch { reported = ($0, $1) }
        try await Task.sleep(for: .milliseconds(150))
        #expect(reported?.1 == "a Wiska")
    }

    @Test func aNewDictationEndsTheWatchAtOnce() async throws {
        let field = Field([(1, "x Wisca"), (1, "x Wiska")])
        var reported: (String, String)?
        let watcher = CorrectionWatcher(read: { field.next() }, settle: .milliseconds(1),
                                        interval: .milliseconds(5), duration: .seconds(10))
        watcher.watch { reported = ($0, $1) }
        try await Task.sleep(for: .milliseconds(50))
        watcher.finish()
        #expect(reported?.1 == "x Wiska")
    }
}
