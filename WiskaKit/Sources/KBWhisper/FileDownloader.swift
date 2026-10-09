import Core
import Foundation

public protocol FileDownloader: Sendable {
    /// Downloads `url` to `destination`; `progress` goes from 0 to 1.
    func download(from url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws
}

public struct URLSessionFileDownloader: FileDownloader {
    public init() {}

    public func download(from url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        try await ProgressDownload.download(from: url, to: destination, progress: progress)
    }
}
