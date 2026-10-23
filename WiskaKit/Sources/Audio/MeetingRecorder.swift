import AVFoundation
import Core
import Observation
import ScreenCaptureKit

/// Records a meeting: the Mac's own audio (the call: everyone else) and the microphone (you), as
/// two 16 kHz mono files in a temporary folder, through ScreenCaptureKit. Needs the "Screen &
/// System Audio Recording" permission; Wiska's own sounds are left out.
@MainActor @Observable
public final class MeetingRecorder {
    private static let log = Log.logger("Audio")

    public enum RecorderError: Error, Equatable {
        /// The permission is missing (or the system refused to share any display).
        case notAllowed
    }

    /// The finished recording: each side's file, for `AudioFileLoader`.
    public struct Recording: Sendable {
        public let others: URL
        public let you: URL
        public let folder: URL
    }

    private var stream: SCStream?
    @ObservationIgnored private var sink: Sink?
    public private(set) var startedAt: Date?
    /// A start in progress: a second click meanwhile must not open a second capture.
    @ObservationIgnored private var starting = false

    public init() {}

    /// Observable, so the menu's "Recording Meeting…" and the Transcribe window follow it.
    public var isRecording: Bool { stream != nil }

    /// The latest loudness of each side (0…1), for meters.
    public var levels: (you: Float, others: Float) { sink?.levels ?? (0, 0) }

    public func start() async throws {
        guard stream == nil, !starting else { return }
        starting = true
        defer { starting = false }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            Self.log.error("meeting: no screen capture permission: \(Log.summary(error), privacy: .public)")
            throw RecorderError.notAllowed
        }
        guard let display = content.displays.first else { throw RecorderError.notAllowed }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.captureMicrophone = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 1
        // Video can't be switched off: keep it tiny and rare.
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Wiska-meeting-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let sink = try Sink(folder: folder)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(sink, type: .audio, sampleHandlerQueue: sink.queue)
        try stream.addStreamOutput(sink, type: .microphone, sampleHandlerQueue: sink.queue)
        try await stream.startCapture()
        self.stream = stream
        self.sink = sink
        startedAt = Date()
        Self.log.notice("meeting: recording started")
    }

    /// Stops and returns the two files.
    public func stop() async throws -> Recording? {
        guard let stream, let sink else { return nil }
        self.stream = nil
        self.sink = nil
        startedAt = nil
        try? await stream.stopCapture()
        let recording = sink.close()
        Self.log.notice("meeting: recording stopped")
        return recording
    }

    /// Receives both sides on one serial queue and writes them as 16 kHz mono.
    private final class Sink: NSObject, SCStreamOutput, @unchecked Sendable {
        let queue = DispatchQueue(label: "Wiska.meeting")
        private let folder: URL
        private var writers: [SCStreamOutputType: Writer] = [:]
        private let lock = NSLock()
        private var latest: (you: Float, others: Float) = (0, 0)

        init(folder: URL) throws {
            self.folder = folder
            super.init()
            writers[.audio] = try Writer(url: folder.appendingPathComponent("others.caf"))
            writers[.microphone] = try Writer(url: folder.appendingPathComponent("you.caf"))
        }

        var levels: (you: Float, others: Float) { lock.withLock { latest } }

        func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
            guard let writer = writers[type], sampleBuffer.isValid,
                  let description = sampleBuffer.formatDescription else { return }
            let format = AVAudioFormat(cmAudioFormatDescription: description)
            try? sampleBuffer.withAudioBufferList { list, _ in
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: list.unsafePointer) else { return }
                let level = writer.write(buffer)
                lock.withLock {
                    if type == .microphone { latest.you = level } else { latest.others = level }
                }
            }
        }

        func close() -> Recording {
            queue.sync {
                writers.values.forEach { $0.close() }
                return Recording(others: folder.appendingPathComponent("others.caf"),
                                 you: folder.appendingPathComponent("you.caf"), folder: folder)
            }
        }
    }

    /// One side: converted to 16 kHz mono as it arrives and appended to a file.
    private final class Writer {
        private var file: AVAudioFile?
        private var converter: PCMConverter?
        private var inputFormat: AVAudioFormat?

        init(url: URL) throws {
            file = try AVAudioFile(forWriting: url, settings: AVAudioFormat.speech16kMono.settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        }

        /// Writes the buffer; returns its loudness (0…1).
        func write(_ buffer: AVAudioPCMBuffer) -> Float {
            guard let file else { return 0 }
            if inputFormat != buffer.format {
                inputFormat = buffer.format
                converter = try? PCMConverter(from: buffer.format, to: .speech16kMono)
            }
            guard let converted = try? converter?.convert(buffer), converted.frameLength > 0 else { return 0 }
            try? file.write(from: converted)
            let samples = converted.floatSamples
            let power = samples.reduce(0) { $0 + $1 * $1 } / Float(max(samples.count, 1))
            return min(1, power.squareRoot() * 4)
        }

        func close() { file = nil }
    }
}
