import Core
import Foundation

/// Who said it: the microphone is you; the Mac's own audio (the call) is everyone else, or,
/// with speakers told apart by voice, one numbered person each.
public enum Speaker: Hashable, Sendable {
    case you, others
    case person(Int)

    public var displayName: String {
        switch self {
        case .you: "You"
        case .others: "Others"
        case .person(let number): "Speaker \(number)"
        }
    }
}

/// One stretch of one voice, from speaker diarization (seconds from the start).
public struct VoiceSegment: Equatable, Sendable {
    public let speaker: String
    public let start: Double
    public let end: Double

    public init(speaker: String, start: Double, end: Double) {
        self.speaker = speaker
        self.start = start
        self.end = end
    }
}

/// A turn to transcribe: who, and where in the call's audio.
public struct MeetingTurn: Equatable, Sendable {
    public let speaker: Speaker
    public let range: Range<Int>
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

    /// `othersTurns`: the call's audio split by voice (`turns(from:)`); without it, the call is
    /// one speaker, "Others", cut at its pauses.
    public static func run(you: [Float], others: [Float], othersTurns: [MeetingTurn]? = nil,
                           every seconds: Double = 20, searching window: Double = 4,
                           session: @MainActor (Speaker) async throws -> any TranscriptionSession,
                           progress: @MainActor (Double) -> Void) async throws -> [MeetingSegment] {
        let yours = pieces(you, every: seconds, searching: window).map { (Speaker.you, you, $0) }
        let theirs = othersTurns.map { $0.map { ($0.speaker, others, $0.range) } }
            ?? pieces(others, every: seconds, searching: window).map { (Speaker.others, others, $0) }
        let work = yours + theirs
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

    /// Diarization's segments as turns: a speaker's segments less than `gap` seconds apart become
    /// one turn, turns longer than `maxSeconds` are split (an engine works best on short stretches),
    /// and speakers are numbered in the order they first speak.
    nonisolated public static func turns(from segments: [VoiceSegment], sampleCount: Int, maxSeconds: Double = 30,
                                         gap: Double = 1.5) -> [MeetingTurn] {
        var numbers: [String: Int] = [:]
        var merged: [(speaker: String, start: Double, end: Double)] = []
        for segment in segments.sorted(by: { $0.start < $1.start }) where segment.end > segment.start {
            if numbers[segment.speaker] == nil { numbers[segment.speaker] = numbers.count + 1 }
            if let last = merged.last, last.speaker == segment.speaker, segment.start - last.end < gap {
                merged[merged.count - 1].end = max(last.end, segment.end)
            } else {
                merged.append((segment.speaker, segment.start, segment.end))
            }
        }
        let rate = AudioChunk.sampleRate
        let longest = Int(maxSeconds * rate)
        return merged.flatMap { turn -> [MeetingTurn] in
            let start = min(max(Int(turn.start * rate), 0), sampleCount)
            let end = min(max(Int(turn.end * rate), start), sampleCount)
            guard end > start else { return [] }
            let speaker = Speaker.person(numbers[turn.speaker] ?? 0)
            return stride(from: start, to: end, by: longest).map { MeetingTurn(speaker: speaker, range: $0..<min($0 + longest, end)) }
        }
    }

    /// One line per person on the call to recognise them by: their longest.
    public static func samples(_ segments: [MeetingSegment]) -> [(speaker: Speaker, line: String)] {
        var best: [Speaker: String] = [:]
        var order: [Speaker] = []
        for segment in segments {
            guard case .person = segment.speaker else { continue }
            if best[segment.speaker] == nil { order.append(segment.speaker) }
            if segment.text.count > (best[segment.speaker]?.count ?? 0) { best[segment.speaker] = segment.text }
        }
        return order.map { ($0, best[$0] ?? "") }
    }

    /// "Speaker 1" → "Anna" in any text (the notes); "Speaker 10" stays itself.
    public static func rename(_ text: String, names: [Speaker: String]) -> String {
        var result = text
        for (speaker, name) in names {
            let name = name.trimmingCharacters(in: .whitespaces)
            guard case .person(let number) = speaker, !name.isEmpty else { continue }
            result = result.replacing(try! Regex("\\bSpeaker \(number)\\b"), with: name)
        }
        return result
    }

    /// "[1:05] Others: …", one paragraph per turn (a speaker's consecutive pieces together).
    public static func transcript(_ segments: [MeetingSegment], names: [Speaker: String] = [:]) -> String {
        var turns: [MeetingSegment] = []
        for segment in segments {
            if let last = turns.last, last.speaker == segment.speaker {
                turns[turns.count - 1].text += " " + segment.text
            } else {
                turns.append(segment)
            }
        }
        return turns.map { turn in
            let name = names[turn.speaker].map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
            return "[\(time(turn.start))] \(name ?? turn.speaker.displayName): \(turn.text)"
        }.joined(separator: "\n\n")
    }

    static func time(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let (hours, minutes, secs) = (total / 3_600, total / 60 % 60, total % 60)
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }
}
