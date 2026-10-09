import Foundation
import Testing
@testable import KBWhisper

final class Reports: @unchecked Sendable { var values: [Double] = []; let lock = NSLock()
    func add(_ v: Double) { lock.lock(); values.append(v); lock.unlock() } }

/// `WISKA_PROBE=1 swift test --filter ProgressProbeTests`: a real 30 MB download (network).
struct ProgressProbeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WISKA_PROBE"] == "1"))
    func progressIsReported() async throws {
        let reports = Reports()
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("probe-\(UUID()).bin")
        try await URLSessionFileDownloader().download(
            from: URL(string: "https://huggingface.co/KBLab/kb-whisper-tiny/resolve/main/ggml-model-q5_0.bin")!,
            to: destination, progress: { reports.add($0) })
        print("PROBE reports:", reports.values.count, reports.values.prefix(3), reports.values.suffix(2))
        #expect(reports.values.count > 10)   // the 30 MB download reports as it goes, not only at the end
        try? FileManager.default.removeItem(at: destination)
    }
}
