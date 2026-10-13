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

        public init(text: String, language: Language?) {
            self.text = text
            self.language = language
        }
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
        // A paragraph per piece (about two minutes of speech).
        return Result(text: texts.joined(separator: "\n\n"), language: language)
    }

    /// Cleans a transcript paragraph by paragraph, in chunks of whole sentences of at most
    /// `maxWords` (what a model rewrites well in one go). A chunk the cleaner can't do stays as it was.
    public static func cleanUp(_ text: String, maxWords: Int = 80,
                               clean: @MainActor (String) async throws -> String,
                               progress: @MainActor (Double) -> Void) async throws -> String {
        let paragraphs = text.components(separatedBy: "\n\n").map { chunks($0, maxWords: maxWords) }
        let total = max(paragraphs.reduce(0) { $0 + $1.count }, 1)
        var done = 0
        var cleaned: [String] = []
        progress(0)
        for chunks in paragraphs {
            var parts: [String] = []
            for chunk in chunks {
                try Task.checkCancellation()
                do {
                    let result = try await clean(chunk).trimmingCharacters(in: .whitespacesAndNewlines)
                    parts.append(result.isEmpty ? chunk : result)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    parts.append(chunk)
                }
                done += 1
                progress(Double(done) / Double(total))
            }
            cleaned.append(parts.joined(separator: " "))
        }
        progress(1)
        return cleaned.joined(separator: "\n\n")
    }

    /// Whole sentences, gathered up to `maxWords` per chunk; a longer sentence is a chunk of its own.
    nonisolated static func chunks(_ paragraph: String, maxWords: Int) -> [String] {
        var sentences: [String] = []
        var current = ""
        for character in paragraph {
            current.append(character)
            if ".!?".contains(character) {
                sentences.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rest.isEmpty { sentences.append(rest) }
        var chunks: [String] = []
        var chunk: [String] = []
        for sentence in sentences where !sentence.isEmpty {
            if !chunk.isEmpty, Log.words((chunk + [sentence]).joined(separator: " ")) > maxWords {
                chunks.append(chunk.joined(separator: " "))
                chunk = []
            }
            chunk.append(sentence)
        }
        if !chunk.isEmpty { chunks.append(chunk.joined(separator: " ")) }
        return chunks
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
