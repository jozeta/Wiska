/// Real-audio Parakeet tests take turns: run in parallel they compete for the Neural Engine,
/// and the latency test would measure the competition instead of Wiska.
@MainActor
enum RealAudioGate {
    private static var busy = false

    static func run<T>(_ body: () async throws -> T) async throws -> T {
        while busy { try await Task.sleep(for: .milliseconds(20)) }
        busy = true
        defer { busy = false }
        return try await body()
    }
}
