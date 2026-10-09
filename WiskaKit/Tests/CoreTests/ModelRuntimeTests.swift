import Foundation
import Testing
@testable import Core

actor Concurrency {
    private(set) var running = 0
    private(set) var most = 0
    private(set) var runs = 0
    func enter() { running += 1; runs += 1; most = max(most, running) }
    func leave() { running -= 1 }
}

/// whisper.cpp may not run twice at once on one model: calls wait for each other.
struct ModelRuntimeTests {
    let directory = URL(fileURLWithPath: "/tmp/model")

    @Test func callsRunOneAtATime() async throws {
        let runtime = ModelRuntime<Int> { _ in 1 }
        let tracker = Concurrency()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    try await runtime.use(from: directory) { _ in
                        await tracker.enter()
                        try await Task.sleep(for: .milliseconds(50))
                        await tracker.leave()
                    }
                }
            }
            try await group.waitForAll()
        }
        #expect(await tracker.most == 1)
        #expect(await tracker.runs == 4)
    }

    /// A request that timed out while the model was loading never runs afterwards.
    @Test func cancelledRequestDoesNotRun() async throws {
        let runtime = ModelRuntime<Int> { _ in
            try? await Task.sleep(for: .milliseconds(200))
            return 1
        }
        let tracker = Concurrency()
        let request = Task {
            try await runtime.use(from: directory) { _ in await tracker.enter(); await tracker.leave() }
        }
        try await Task.sleep(for: .milliseconds(50))
        request.cancel()
        _ = await request.result
        try await Task.sleep(for: .milliseconds(300))
        #expect(await tracker.runs == 0)
    }
}

/// Cancel at the moment a download starts: no crash ("task created in an invalidated session").
struct ProgressDownloadCancelTests {
    @Test func cancelledBeforeStartingThrowsInsteadOfCrashing() async {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("never-\(UUID()).bin")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await ProgressDownload.download(from: URL(string: "https://example.invalid/file")!, to: destination,
                                                progress: { _ in })
        }
        await #expect(throws: (any Error).self) { try await task.value }
    }
}
