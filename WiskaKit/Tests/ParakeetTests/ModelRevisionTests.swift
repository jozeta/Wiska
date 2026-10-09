import Foundation
import Testing
@testable import Parakeet

@MainActor
struct ModelRevisionTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pkrev-\(UUID().uuidString)")

    @Test func decodesTheHuggingFaceResponse() throws {
        let json = #"{"_id":"x","id":"FluidInference/parakeet-tdt-0.6b-v3-coreml","sha":"7dd20fe6","lastModified":"2026-08-19T20:10:29.000Z","private":false}"#
        let revision = try HuggingFaceRevisionSource.decode(Data(json.utf8))
        #expect(revision.sha == "7dd20fe6")
        #expect(revision.lastModified == Date(timeIntervalSince1970: 1_787_170_229))
    }

    @Test func decodesDatesWithoutFractionalSeconds() throws {
        let json = #"{"sha":"a","lastModified":"2026-08-19T20:10:29Z"}"#
        #expect(try HuggingFaceRevisionSource.decode(Data(json.utf8)).sha == "a")
    }

    @Test func missingFieldsAreAnError() {
        #expect(throws: (any Error).self) { try HuggingFaceRevisionSource.decode(Data(#"{"sha":"a"}"#.utf8)) }
    }

    @Test func downloadRecordsTheRevision() async throws {
        let store = ParakeetModelStore(directory: dir, downloader: FakeDownloader(installed: false))
        store.download(revision: "abc123")
        for _ in 0..<200 { if case .downloading = store.status { try await Task.sleep(for: .milliseconds(10)) } }
        #expect(store.status == .ready)
        #expect(store.installedRevision == "abc123")
        #expect(store.installedAt != nil)
    }

    @Test func plainDownloadHasNoRevisionUntilRecorded() async throws {
        let store = ParakeetModelStore(directory: dir, downloader: FakeDownloader(installed: false))
        store.download()
        for _ in 0..<200 { if case .downloading = store.status { try await Task.sleep(for: .milliseconds(10)) } }
        #expect(store.installedRevision == nil)
        store.recordRevision("def456")
        #expect(store.installedRevision == "def456")
        // A recorded revision survives a relaunch.
        #expect(ParakeetModelStore(directory: dir, downloader: FakeDownloader(installed: true)).installedRevision == "def456")
    }

    @Test func decodesTheFileList() throws {
        let json = #"{"sha":"a","lastModified":"2026-08-19T20:10:29.000Z","siblings":[{"rfilename":"Encoder.mlmodelc/w.bin","blobId":"b1","size":1},{"rfilename":"README.md","blobId":"b2"}]}"#
        let revision = try HuggingFaceRevisionSource.decode(Data(json.utf8))
        #expect(revision.files == ["Encoder.mlmodelc/w.bin": "b1", "README.md": "b2"])
    }

    @Test func installedComponentsAreTheTopLevelEntries() async throws {
        let store = ParakeetModelStore(directory: dir, downloader: FakeDownloader(installed: false))
        store.download()
        for _ in 0..<200 { if case .downloading = store.status { try await Task.sleep(for: .milliseconds(10)) } }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Encoder.mlmodelc"),
                                                withIntermediateDirectories: true)
        #expect(store.installedComponents.contains("Encoder.mlmodelc"))
        #expect(!store.installedComponents.contains(ParakeetModelStore.completionMarker))
    }
}
