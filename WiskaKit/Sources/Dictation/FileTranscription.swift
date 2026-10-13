import Core
import Foundation

/// Transcribes a recording in pieces of about `every` seconds, each cut at the quietest moment
/// near its end, so no word is split and progress can be shown. Each piece gets its own session
/// from the same engine a dictation would use.
@MainActor
public enum FileTranscription {
    public struct Result: Sendable, Equatable {
        public let text: String
        /// The language the engine heard most (by words), when it says.
        public let language: Language?
    }

    public static func run(_ samples: [Float], every seconds: Double = 120, searching window: Double = 5,
                           session: @MainActor () async throws -> any TranscriptionSession,
                           progress: @MainActor (Double) -> Void) async throws -> Result {
        let bounds = [0] + cuts(samples, every: seconds, searching: window) + [samples.count]
        var texts: [String] = []
        var words: [Language: Int] = [:]
        progress(0)
        for (start, end) in zip(bounds, bounds.dropFirst()) where end > start {
            try Task.checkCancellation()
            let piece = try await session()
            let chunk = 16_000
            for offset in stride(from: start, to: end, by: chunk) {
                piece.append(AudioChunk(samples: Array(samples[offset..<min(offset + chunk, end)])))
            }
            let transcript = try await piece.finish()
            let text = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                texts.append(text)
                if let language = transcript.language { words[language, default: 0] += Log.words(text) }
            }
            progress(Double(end) / Double(max(samples.count, 1)))
        }
        progress(1)
        let language = words.max { $0.value != $1.value ? $0.value < $1.value : $0.key.rawValue > $1.key.rawValue }?.key
        return Result(text: texts.joined(separator: " "), language: language)
    }

    /// Where to cut: about every `seconds`, at the quietest tenth of a second within `window`
    /// seconds before or after. None for audio shorter than one and a half pieces.
    nonisolated static func cuts(_ samples: [Float], every seconds: Double, searching window: Double) -> [Int] {
        let rate = Int(AudioChunk.sampleRate)
        let step = Int(seconds * Double(rate))
        let reach = Int(window * Double(rate))
        let frame = rate / 10
        var cuts: [Int] = []
        var target = step
        while target + step / 2 < samples.count {
            let low = max((cuts.last ?? 0) + frame, target - reach)
            let high = min(samples.count - frame, target + reach)
            var best = target
            var quietest = Float.greatestFiniteMagnitude
            for start in stride(from: low, through: high, by: frame / 2) {
                var energy: Float = 0
                for index in start..<start + frame { energy += samples[index] * samples[index] }
                if energy < quietest {
                    quietest = energy
                    best = start + frame / 2
                }
            }
            cuts.append(best)
            target = best + step
        }
        return cuts
    }
}
