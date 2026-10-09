import FluidAudio
import Foundation

/// One published state of the model repo on Hugging Face.
public struct ModelRevision: Equatable, Sendable {
    public let sha: String
    public let lastModified: Date

    public init(sha: String, lastModified: Date) {
        self.sha = sha
        self.lastModified = lastModified
    }
}

public protocol ModelRevisionSource: Sendable {
    func latestRevision() async throws -> ModelRevision
}

/// Asks Hugging Face which revision of the model repo is current. One small request; nothing
/// about the user is sent. Used only for update checks, never to download.
public struct HuggingFaceRevisionSource: ModelRevisionSource {
    struct BadResponse: Error {}
    private struct Body: Decodable {
        let sha: String
        let lastModified: String
    }

    private let url: URL
    private let session: URLSession

    public init(repo: String = Repo.parakeetV3.rawValue, session: URLSession = .shared) {
        self.url = URL(string: "https://huggingface.co/api/models/\(repo)")!
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
        return ModelRevision(sha: body.sha, lastModified: date)
    }
}
