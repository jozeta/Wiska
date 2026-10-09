import Synchronization

/// Resumes a continuation exactly once, from whichever racer gets there first.
public final class ResumeOnce: Sendable {
    private let continuation: Mutex<CheckedContinuation<String, Error>?>

    public init(_ continuation: CheckedContinuation<String, Error>) {
        self.continuation = Mutex(continuation)
    }

    public func resume(_ result: Result<String, Error>) {
        continuation.withLock { pending in
            pending?.resume(with: result)
            pending = nil
        }
    }
}
