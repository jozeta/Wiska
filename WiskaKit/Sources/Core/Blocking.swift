import Dispatch

/// Runs slow, blocking work (reading the log, decoding a long recording) on a dispatch queue:
/// Swift's cooperative threads must never wait, or every task in the app slows down with them.
public func runBlocking<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(with: Result { try work() })
        }
    }
}
