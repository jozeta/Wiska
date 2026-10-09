import Core
import Foundation
import Testing
@testable import LocalModel

final class FakeLoadedModel: LoadedModel {
    func respond(system: String, prompt: String, maxTokens: Int) async throws -> String { "answer: \(prompt)" }
}

actor LoadCounter {
    private(set) var loads = 0
    func increment() { loads += 1 }
}

struct GemmaRuntimeTests {
    let directory = URL(fileURLWithPath: "/tmp/gemma")

    /// Two requests while loading share one load (the first dictation after launch).
    @Test func concurrentRequestsShareOneLoad() async throws {
        let counter = LoadCounter()
        let runtime = GemmaRuntime { _ in
            await counter.increment()
            try await Task.sleep(for: .milliseconds(200))
            return FakeLoadedModel()
        }
        async let first = runtime.generate(directory: directory, system: "s", prompt: "a", maxTokens: 10)
        async let second = runtime.generate(directory: directory, system: "s", prompt: "b", maxTokens: 10)
        let answers = try await [first, second]
        #expect(answers == ["answer: a", "answer: b"])
        #expect(await counter.loads == 1)
        #expect(await runtime.isLoaded)
    }

    @Test func idleModelIsUnloaded() async throws {
        let runtime = GemmaRuntime(idleLimit: .milliseconds(100)) { _ in FakeLoadedModel() }
        _ = try await runtime.generate(directory: directory, system: "s", prompt: "a", maxTokens: 10)
        #expect(await runtime.isLoaded)
        try await Task.sleep(for: .milliseconds(400))
        #expect(await !runtime.isLoaded)
    }

    @Test func loadFailureIsNamed() async {
        let runtime = GemmaRuntime { _ in throw CocoaError(.fileReadCorruptFile) }
        await #expect(throws: LocalModelError.self) {
            try await runtime.generate(directory: directory, system: "s", prompt: "a", maxTokens: 10)
        }
    }
}

@MainActor
struct GemmaModelTests {
    func readyStore() -> GemmaModelStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gemma-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data().write(to: directory.appendingPathComponent(GemmaModelStore.completionMarker))
        return GemmaModelStore(directory: directory, downloader: FakeRepoDownloader(), freeSpace: { nil })
    }

    @Test func availableOnlyWhenInstalledAndLoadable() async throws {
        let model = GemmaModel(store: readyStore(), runtime: GemmaRuntime { _ in FakeLoadedModel() })
        #expect(model.isAvailable)
        #expect(try await model.generate(system: "s", prompt: "hi", maxTokens: 10) == "answer: hi")
        #expect(model.isLoaded)

        let broken = GemmaModel(store: readyStore(), runtime: GemmaRuntime { _ in throw CocoaError(.fileReadCorruptFile) })
        await #expect(throws: LocalModelError.self) { try await broken.generate(system: "s", prompt: "hi", maxTokens: 10) }
        #expect(!broken.isAvailable)
        #expect(broken.loadError != nil)
        broken.remove()
        #expect(broken.loadError == nil)

        let missing = GemmaModel(store: GemmaModelStore(directory: URL(fileURLWithPath: "/tmp/none-\(UUID())"),
                                                        downloader: FakeRepoDownloader(), freeSpace: { nil }),
                                 runtime: GemmaRuntime { _ in FakeLoadedModel() })
        #expect(!missing.isAvailable)
    }

    @Test func statusTexts() {
        #expect(GemmaModel.statusText(.notDownloaded, loaded: false, loadError: nil) == "Not downloaded")
        #expect(GemmaModel.statusText(.downloading(0.42), loaded: false, loadError: nil) == "Downloading 42 %")
        #expect(GemmaModel.statusText(.ready, loaded: false, loadError: nil) == "Ready")
        #expect(GemmaModel.statusText(.ready, loaded: true, loadError: nil) == "Loaded")
        #expect(GemmaModel.statusText(.ready, loaded: false, loadError: "bad file") == "Couldn't load: bad file")
        #expect(GemmaModel.statusText(.failed("Download failed — try again"), loaded: false, loadError: nil)
                == "Download failed — try again")
    }
}
