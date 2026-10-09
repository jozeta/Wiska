import Foundation

/// Downloads one URL to a file and reports progress. (`URLSession.download(from:delegate:)`
/// never calls the task delegate's `didWriteData`, so its progress stayed at 0 % for 5 GB.)
public enum ProgressDownload {
    public static func download(from url: URL, to destination: URL,
                                progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let run = Run(destination: destination, report: progress)
        let session = URLSession(configuration: .default, delegate: run, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        // The task exists before any cancel can arrive; cancelling it (even before it starts)
        // still ends in didCompleteWithError, so the continuation is resumed exactly once.
        let task = session.downloadTask(with: url)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                run.start(continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    private final class Run: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let destination: URL
        let report: @Sendable (Double) -> Void
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Error>?
        private var failure: Error?

        init(destination: URL, report: @escaping @Sendable (Double) -> Void) {
            self.destination = destination
            self.report = report
        }

        func start(_ continuation: CheckedContinuation<Void, Error>) {
            lock.withLock { self.continuation = continuation }
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            guard totalBytesExpectedToWrite > 0 else { return }
            report(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }

        /// The temporary file is deleted when this returns: move it now.
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            do {
                guard let http = downloadTask.response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: location, to: destination)
            } catch {
                lock.withLock { failure = error }
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            let pending = lock.withLock { () -> (CheckedContinuation<Void, Error>?, Error?) in
                defer { continuation = nil }
                return (continuation, error ?? failure)
            }
            if let error = pending.1 { pending.0?.resume(throwing: error) } else { pending.0?.resume() }
        }
    }
}
