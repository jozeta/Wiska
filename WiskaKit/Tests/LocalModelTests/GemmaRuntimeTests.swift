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

actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

/// Review fixes: memory is given back, a load nobody wants any more is dropped, and the
/// model is loaded early again after an idle unload.
struct GemmaRuntimeLifecycleTests {
    let directory = URL(fileURLWithPath: "/tmp/gemma")

    /// A model loaded early (fn press) but never used is still let go after the idle time.
    @Test func loadAloneIsUnloadedWhenIdle() async throws {
        let runtime = GemmaRuntime(idleLimit: .milliseconds(100)) { _ in FakeLoadedModel() }
        _ = try await runtime.load(from: directory)
        #expect(await runtime.isLoaded)
        try await Task.sleep(for: .milliseconds(400))
        #expect(await !runtime.isLoaded)
    }

    /// Remove (or switching to Apple) during a load: the finished load is thrown away.
    @Test func unloadDuringLoadDiscardsTheLoad() async throws {
        let runtime = GemmaRuntime { _ in
            try await Task.sleep(for: .milliseconds(200))
            return FakeLoadedModel()
        }
        let load = Task { try await runtime.load(from: directory) }
        try await Task.sleep(for: .milliseconds(50))
        await runtime.unload()
        await #expect(throws: (any Error).self) { try await load.value }
        #expect(await !runtime.isLoaded)
    }

    /// Unloading hands MLX's buffer cache back and tells whoever shows "Loaded".
    @Test func unloadReleasesMemoryAndReports() async throws {
        let released = Counter()
        let reported = Counter()
        let runtime = GemmaRuntime(idleLimit: .milliseconds(100), release: { Task { await released.increment() } }) { _ in
            FakeLoadedModel()
        }
        await runtime.setOnUnload { Task { await reported.increment() } }
        _ = try await runtime.load(from: directory)
        try await Task.sleep(for: .milliseconds(400))
        #expect(await released.value == 1)
        #expect(await reported.value == 1)
    }
}

@MainActor
struct GemmaModelLifecycleTests {
    func readyStore() -> GemmaModelStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gemma-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data().write(to: directory.appendingPathComponent(GemmaModelStore.completionMarker))
        return GemmaModelStore(directory: directory, downloader: FakeRepoDownloader(), freeSpace: { nil })
    }

    /// After the idle unload, the next fn press loads the model again (not after release).
    @Test func prepareLoadsAgainAfterIdleUnload() async throws {
        let loads = Counter()
        let model = GemmaModel(store: readyStore(), runtime: GemmaRuntime(idleLimit: .milliseconds(150)) { _ in
            await loads.increment()
            return FakeLoadedModel()
        })
        model.prepare()
        try await Task.sleep(for: .milliseconds(80))
        #expect(model.isLoaded)
        try await Task.sleep(for: .milliseconds(400))
        #expect(!model.isLoaded)
        model.prepare()
        try await Task.sleep(for: .milliseconds(80))
        #expect(model.isLoaded)
        #expect(await loads.value == 2)
    }

    /// Remove while loading: the load that fails afterwards (files gone) doesn't mark Gemma broken.
    @Test func removeDuringLoadIgnoresItsResult() async throws {
        let model = GemmaModel(store: readyStore(), runtime: GemmaRuntime { _ in
            try await Task.sleep(for: .milliseconds(150))
            throw CocoaError(.fileReadNoSuchFile)
        })
        model.prepare()
        try await Task.sleep(for: .milliseconds(30))
        model.remove()
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.loadError == nil)
        #expect(!model.isLoaded)
    }
}
