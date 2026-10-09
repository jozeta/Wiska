import Foundation

public protocol RepoDownloader: Sendable {
    /// Downloads the model's files into `directory`; `progress` goes from 0 to 1.
    func download(to directory: URL, progress: @escaping @Sendable (Double) -> Void) async throws
}

/// Every file of a Hugging Face model repo at its current commit, fetched only when the user
/// clicks Download.
public struct HuggingFaceRepoDownloader: RepoDownloader {
    let repo: String
    let session: URLSession

    public init(repo: String, session: URLSession = .shared) {
        self.repo = repo
        self.session = session
    }

    struct Listing: Decodable {
        struct File: Decodable { let rfilename: String; let size: Int? }
        let sha: String
        let siblings: [File]
    }

    public func download(to directory: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let api = URL(string: "https://huggingface.co/api/models/\(repo)?blobs=true")!
        let (data, response) = try await session.data(from: api)
        try Self.check(response)
        let listing = try JSONDecoder().decode(Listing.self, from: data)
        let files = listing.siblings.filter { !$0.rfilename.hasPrefix(".") && $0.rfilename != "README.md" }
        let total = max(1, files.reduce(0) { $0 + ($1.size ?? 0) })
        var done = 0
        for file in files {
            try Task.checkCancellation()
            let url = URL(string: "https://huggingface.co/\(repo)/resolve/\(listing.sha)/\(file.rfilename)")!
            let destination = directory.appendingPathComponent(file.rfilename)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let base = done
            let delegate = ProgressDelegate { written in progress(Double(base + written) / Double(total)) }
            let (temporary, fileResponse) = try await session.download(from: url, delegate: delegate)
            try Self.check(fileResponse)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporary, to: destination)
            done += file.size ?? 0
            progress(Double(done) / Double(total))
        }
    }

    static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}

/// Byte progress of one file (the weights are a single 5 GB file).
private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    let report: @Sendable (Int) -> Void
    init(report: @escaping @Sendable (Int) -> Void) { self.report = report }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        report(Int(totalBytesWritten))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
