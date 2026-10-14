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
    /// Who was still talking when this turn began (their audio kept the overlap).
    public var over: Speaker? = nil
}

public struct MeetingSegment: Equatable, Sendable {
    public let speaker: Speaker
    /// Seconds from the start of the recording.
    public let start: TimeInterval
    public var text: String
    /// Who this person started talking over, if anyone.
    public var over: Speaker?

    public init(speaker: Speaker, start: TimeInterval, text: String, over: Speaker? = nil) {
        self.speaker = speaker
        self.start = start
        self.text = text
        self.over = over
    }
}

/// A recorded meeting to a transcript: each side is cut into short pieces at its pauses,
/// silent pieces are skipped, and what was said is put back in order of time.
@MainActor
public enum MeetingTranscription {
    private nonisolated static let log = Log.logger("Dictation")

    /// Quieter than this (RMS) is silence: nothing to transcribe.
    nonisolated static let silence: Float = 0.004

    /// `othersTurns`: the call's audio split by voice (`turns(from:)`); without it, the call is
    /// one speaker, "Others", cut at its pauses. Pieces are short (about `seconds`) so that when
    /// you and the call talk at once, the lines still come out in the order they were said.
    public static func run(you: [Float], others: [Float], othersTurns: [MeetingTurn]? = nil,
                           every seconds: Double = 10, searching window: Double = 3,
                           session: @MainActor (Speaker) async throws -> any TranscriptionSession,
                           progress: @MainActor (Double) -> Void) async throws -> [MeetingSegment] {
        let (you, removed) = withoutBleed(you, call: others)
        if removed > 0 {
            log.notice("meeting: \(Double(removed) / AudioChunk.sampleRate, format: .fixed(precision: 1), privacy: .public) s of the call's sound left out of the microphone")
        }
        let yours = pieces(you, every: seconds, searching: window).map { (Speaker.you, you, $0, Speaker?.none) }
        let theirs = othersTurns.map { $0.map { ($0.speaker, others, $0.range, $0.over) } }
            ?? pieces(others, every: seconds, searching: window).map { (Speaker.others, others, $0, Speaker?.none) }
        let work = yours + theirs
        var segments: [MeetingSegment] = []
        progress(0)
        for (index, (speaker, samples, piece, over)) in work.enumerated() {
            try Task.checkCancellation()
            let transcriber = try await session(speaker)
            for offset in stride(from: piece.lowerBound, to: piece.upperBound, by: 16_000) {
                transcriber.append(AudioChunk(samples: Array(samples[offset..<min(offset + 16_000, piece.upperBound)])))
            }
            let text = try await transcriber.finish().text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                segments.append(MeetingSegment(speaker: speaker, start: Double(piece.lowerBound) / AudioChunk.sampleRate,
                                               text: text, over: over))
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
    /// one turn (unless someone else starts in between), and speakers are numbered in the order
    /// they're first heard.
    ///
    /// The call is one mixed track, so audio where two voices overlap is transcribed once, for
    /// whoever was already talking; the other turn starts where theirs ends and is marked `over`
    /// them, and a voice entirely inside someone else's turn has no audio of its own.
    ///
    /// Turns longer than `maxSeconds` are split (an engine works best on short stretches): at a
    /// pause when `audio` is given, else evenly.
    nonisolated public static func turns(from segments: [VoiceSegment], sampleCount: Int, audio: [Float]? = nil,
                                         maxSeconds: Double = 30, gap: Double = 1.5) -> [MeetingTurn] {
        var merged: [(speaker: String, start: Double, end: Double)] = []
        for segment in segments.sorted(by: { $0.start < $1.start }) where segment.end > segment.start {
            if let last = merged.last, last.speaker == segment.speaker, segment.start - last.end < gap {
                merged[merged.count - 1].end = max(last.end, segment.end)
            } else {
                merged.append((segment.speaker, segment.start, segment.end))
            }
        }

        var exclusive: [(speaker: String, start: Double, end: Double, over: String?)] = []
        var covered = -Double.infinity
        var owner: String?
        for turn in merged {
            var start = turn.start
            var over: String?
            if start < covered {
                start = covered
                if owner != turn.speaker { over = owner }
            }
            guard turn.end > start else { continue }   // inside someone else's turn: their audio holds it
            exclusive.append((turn.speaker, start, turn.end, over))
            covered = turn.end
            owner = turn.speaker
        }

        var numbers: [String: Int] = [:]
        for turn in exclusive where numbers[turn.speaker] == nil { numbers[turn.speaker] = numbers.count + 1 }
        let rate = AudioChunk.sampleRate
        let longest = Int(maxSeconds * rate)
        return exclusive.flatMap { turn -> [MeetingTurn] in
            let start = min(max(Int(turn.start * rate), 0), sampleCount)
            let end = min(max(Int(turn.end * rate), start), sampleCount)
            guard end > start else { return [] }
            let speaker = Speaker.person(numbers[turn.speaker] ?? 0)
            let over = turn.over.flatMap { numbers[$0] }.map(Speaker.person)
            var bounds = Array(stride(from: start, to: end, by: longest)) + [end]
            if end - start > longest, let audio, end <= audio.count {
                let cuts = FileTranscription.cuts(Array(audio[start..<end]), every: maxSeconds * 2 / 3, searching: maxSeconds / 6)
                bounds = [start] + cuts.map { $0 + start } + [end]
            }
            return zip(bounds, bounds.dropFirst()).enumerated().map { index, piece in
                MeetingTurn(speaker: speaker, range: piece.0..<piece.1, over: index == 0 ? over : nil)
            }
        }
    }

    /// The microphone without the call leaking in from the speakers: where the call is playing and
    /// the microphone is no louder than that leak (about twice its usual level), the microphone
    /// is silenced. Your own voice, close to the microphone, is much louder and stays; with
    /// headphones there's no leak and nothing changes. Returns how many samples were silenced.
    nonisolated static func withoutBleed(_ mic: [Float], call: [Float]) -> (audio: [Float], removed: Int) {
        let frame = Int(AudioChunk.sampleRate) / 20   // 50 ms
        let count = min(mic.count, call.count) / frame
        guard count > 1 else { return (mic, 0) }
        func rms(_ samples: [Float], _ index: Int) -> Float {
            var energy: Float = 0
            for sample in samples[(index * frame)..<((index + 1) * frame)] { energy += sample * sample }
            return (energy / Float(frame)).squareRoot()
        }
        let heard = (0..<count).map { rms(mic, $0) }
        // The leak comes out of the speakers a little late: compare with this frame and the last.
        let playing = (0..<count).map { max(rms(call, $0), $0 > 0 ? rms(call, $0 - 1) : 0) }
        let ratios = (0..<count).filter { playing[$0] >= silence }.map { heard[$0] / playing[$0] }.sorted()
        guard !ratios.isEmpty else { return (mic, 0) }
        // How loud the leak is: the low end of mic/call while the call plays (you're mostly quiet then).
        let leak = ratios[ratios.count / 4]
        let isLeak = (0..<count).map { playing[$0] >= silence && heard[$0] <= 2 * leak * playing[$0] }

        var audio = mic
        var removed = 0
        var index = 0
        while index < count {
            guard isLeak[index] else { index += 1; continue }
            var end = index
            while end < count && isLeak[end] { end += 1 }
            // Only stretches of 200 ms or more: shorter ones are likely gaps inside your own words.
            if end - index >= 4 {
                let range = (index * frame)..<min(end * frame, audio.count)
                for sample in range { audio[sample] = 0 }
                removed += range.count
            }
            index = end
        }
        return (audio, removed)
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

    /// "[1:05] Others: …", one paragraph per turn (a speaker's consecutive pieces together);
    /// "Speaker 2 (over Anna): …" when someone started while another was still talking.
    public static func transcript(_ segments: [MeetingSegment], names: [Speaker: String] = [:]) -> String {
        var turns: [MeetingSegment] = []
        for segment in segments {
            if let last = turns.last, last.speaker == segment.speaker, segment.over == nil {
                turns[turns.count - 1].text += " " + segment.text
            } else {
                turns.append(segment)
            }
        }
        func name(_ speaker: Speaker) -> String {
            names[speaker].map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
                ?? speaker.displayName
        }
        return turns.map { turn in
            let over = turn.over.map { " (over \(name($0)))" } ?? ""
            return "[\(time(turn.start))] \(name(turn.speaker))\(over): \(turn.text)"
        }.joined(separator: "\n\n")
    }

    static func time(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let (hours, minutes, secs) = (total / 3_600, total / 60 % 60, total % 60)
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }
}
