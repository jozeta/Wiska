import Core
import Foundation

/// Who said it: the microphone is you, the Mac's own audio (the call) is everyone else.
public enum Speaker: String, Sendable, Equatable {
    case you, others

    public var displayName: String { self == .you ? "You" : "Others" }
}

public struct MeetingSegment: Equatable, Sendable {
    public let speaker: Speaker
    /// Seconds from the start of the recording.
    public let start: TimeInterval
    public var text: String

    public init(speaker: Speaker, start: TimeInterval, text: String) {
        self.speaker = speaker
        self.start = start
        self.text = text
    }
}

/// A recorded meeting to a transcript: each side is cut into short pieces at its pauses,
/// silent pieces are skipped, and what was said is put back in order of time.
@MainActor
public enum MeetingTranscription {
    /// Quieter than this (RMS) is silence: nothing to transcribe.
    nonisolated static let silence: Float = 0.004

    public static func run(you: [Float], others: [Float], every seconds: Double = 20, searching window: Double = 4,
                           session: @MainActor (Speaker) async throws -> any TranscriptionSession,
                           progress: @MainActor (Double) -> Void) async throws -> [MeetingSegment] {
        let work = [(Speaker.you, you), (.others, others)].flatMap { speaker, samples in
            pieces(samples, every: seconds, searching: window).map { (speaker, samples, $0) }
        }
        var segments: [MeetingSegment] = []
        progress(0)
        for (index, (speaker, samples, piece)) in work.enumerated() {
            try Task.checkCancellation()
            let transcriber = try await session(speaker)
            for offset in stride(from: piece.lowerBound, to: piece.upperBound, by: 16_000) {
                transcriber.append(AudioChunk(samples: Array(samples[offset..<min(offset + 16_000, piece.upperBound)])))
            }
            let text = try await transcriber.finish().text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                segments.append(MeetingSegment(speaker: speaker, start: Double(piece.lowerBound) / AudioChunk.sampleRate,
                                               text: text))
            }
            progress(Double(index + 1) / Double(work.count))
        }
        progress(1)
        return segments.sorted { $0.start < $1.start }
    }

    /// The stretches worth transcribing: pieces cut at pauses, without the silent ones.
    nonisolated static func pieces(_ samples: [Float], every seconds: Double, searching window: Double) -> [Range<Int>] {
        guard !samples.isEmpty else { return [] }
        let bounds = [0] + FileTranscription.cuts(samples, every: seconds, searching: window) + [samples.count]
        return zip(bounds, bounds.dropFirst()).map { $0..<$1 }.filter { range in
            guard !range.isEmpty else { return false }
            var energy: Float = 0
            for index in range { energy += samples[index] * samples[index] }
            return (energy / Float(range.count)).squareRoot() >= silence
        }
    }

    /// "[1:05] Others: …", one paragraph per turn (a speaker's consecutive pieces together).
    public static func transcript(_ segments: [MeetingSegment]) -> String {
        var turns: [MeetingSegment] = []
        for segment in segments {
            if let last = turns.last, last.speaker == segment.speaker {
                turns[turns.count - 1].text += " " + segment.text
            } else {
                turns.append(segment)
            }
        }
        return turns.map { "[\(time($0.start))] \($0.speaker.displayName): \($0.text)" }.joined(separator: "\n\n")
    }

    static func time(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let (hours, minutes, secs) = (total / 3_600, total / 60 % 60, total % 60)
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }
}
