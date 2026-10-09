import Foundation

public protocol FileDownloader: Sendable {
    /// Downloads `url` to `destination`; `progress` goes from 0 to 1.
    func download(from url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws
}

public struct URLSessionFileDownloader: FileDownloader {
    public init() {}

    public func download(from url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let delegate = DownloadProgress(report: progress)
        let (temporary, response) = try await URLSession.shared.download(from: url, delegate: delegate)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}

private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, Sendable {
    let report: @Sendable (Double) -> Void
    init(report: @escaping @Sendable (Double) -> Void) { self.report = report }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        report(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
