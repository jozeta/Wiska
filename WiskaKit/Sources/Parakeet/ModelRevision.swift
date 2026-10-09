import CryptoKit
import FluidAudio
import Foundation

/// One published state of the model repo on Hugging Face.
public struct ModelRevision: Equatable, Sendable {
    public let sha: String
    public let lastModified: Date
    /// Every file in the repo → its content id (blob id).
    public let files: [String: String]

    public init(sha: String, lastModified: Date, files: [String: String] = [:]) {
        self.sha = sha
        self.lastModified = lastModified
        self.files = files
    }

    /// Identifies the content of just the files Wiska installed (`components`: the top-level folders and
    /// files of the model folder). The repo also holds other model variants and a README; their changes
    /// must not count as an update.
    public func fingerprint(of components: Set<String>) -> String {
        let used = files.filter { components.contains(String($0.key.split(separator: "/").first ?? "")) }
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: "\n")
        let digest = SHA256.hash(data: Data(used.utf8)).map { String(format: "%02x", $0) }.joined()
        return Self.fingerprintPrefix + digest
    }

    static let fingerprintPrefix = "files:"
}

public protocol ModelRevisionSource: Sendable {
    func latestRevision() async throws -> ModelRevision
}

/// Asks Hugging Face which revision of the model repo is current. One small request; nothing
/// about the user is sent. Used only for update checks, never to download.
public struct HuggingFaceRevisionSource: ModelRevisionSource {
    struct BadResponse: Error {}
    private struct Body: Decodable {
        struct Sibling: Decodable {
            let rfilename: String
            let blobId: String?
        }
        let sha: String
        let lastModified: String
        let siblings: [Sibling]?
    }

    private let url: URL
    private let session: URLSession

    public init(repo: String = Repo.parakeetV3.rawValue, session: URLSession = .shared) {
        // blobs=true adds each file's content id, so only the files Wiska uses are compared.
        self.url = URL(string: "https://huggingface.co/api/models/\(repo)?blobs=true")!
        self.session = session
    }

    public func latestRevision() async throws -> ModelRevision {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BadResponse()
        }
        return try Self.decode(data)
    }

    static func decode(_ data: Data) throws -> ModelRevision {
        let body = try JSONDecoder().decode(Body.self, from: data)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        guard let date = fractional.date(from: body.lastModified) ?? plain.date(from: body.lastModified) else {
            throw BadResponse()
        }
        let files = Dictionary((body.siblings ?? []).compactMap { sibling in sibling.blobId.map { (sibling.rfilename, $0) } },
                               uniquingKeysWith: { first, _ in first })
        return ModelRevision(sha: body.sha, lastModified: date, files: files)
    }
}
