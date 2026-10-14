import AVFoundation
import Core
import Foundation
import Speech
import Testing
@testable import SpeechToText

/// Every Apple variant on a real recording, piece by piece; each variant's text is written to
/// WISKA_VOICE_OUT/<variant>.txt for scoring. `WISKA_VOICE_FILE=… WISKA_VOICE_OUT=… swift test --filter VoiceFileTests`
@MainActor
struct VoiceFileTests {
    nonisolated static var file: String? { ProcessInfo.processInfo.environment["WISKA_VOICE_FILE"] }
    static var out: URL { URL(fileURLWithPath: ProcessInfo.processInfo.environment["WISKA_VOICE_OUT"] ?? NSTemporaryDirectory()) }

    static func load(_ path: String) throws -> [Float] {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        return try PCMConverter(from: file.processingFormat, to: .speech16kMono).convert(buffer).floatSamples
    }

    /// About every `seconds`, cut at the quietest 100 ms within ±3 s.
    static func pieces(_ samples: [Float], every seconds: Double = 10) -> [[Float]] {
        let frame = 1_600
        var cuts = [0]
        var target = Int(seconds * 16_000)
        while target + 3 * 16_000 < samples.count {
            var best = target
            var quietest = Float.greatestFiniteMagnitude
            for start in stride(from: target - 3 * 16_000, through: target + 3 * 16_000 - frame, by: frame / 2) {
                let energy = samples[start..<start + frame].reduce(0) { $0 + $1 * $1 }
                if energy < quietest { quietest = energy; best = start + frame / 2 }
            }
            cuts.append(best)
            target = best + Int(seconds * 16_000)
        }
        cuts.append(samples.count)
        return zip(cuts, cuts.dropFirst()).map { Array(samples[$0..<$1]) }
    }

    static func words(_ audio: [Float], _ language: Language, vocabulary: [String] = []) async throws -> [MixedLanguageProbeTests.Word] {
        try await MixedLanguageProbeTests.words(audio, language, vocabulary: vocabulary)
    }

    static func text(_ words: [MixedLanguageProbeTests.Word]) -> String {
        words.map(\.text).joined(separator: " ")
    }

    static func confidence(_ words: [MixedLanguageProbeTests.Word]) -> Double {
        words.isEmpty ? -1 : words.map(\.confidence).reduce(0, +) / Double(words.count)
    }

    @Test(.enabled(if: file != nil), .timeLimit(.minutes(20)))
    func variants() async throws {
        let audio = try Self.load(Self.file!)
        var outputs: [String: [String]] = [:]
        for (index, piece) in Self.pieces(audio).enumerated() {
            let swedish = try await Self.words(piece, .swedish)
            let english = try await Self.words(piece, .english)
            let vocab = try await Self.words(piece, .swedish, vocabulary: SwedishITAutoDetectTests.vocabulary)
            outputs["apple-sv", default: []].append(Self.text(swedish))
            outputs["apple-sv-vocab", default: []].append(Self.text(vocab))
            // Auto-detect as Wiska does it: the more confident language, Swedish on a near tie.
            let svConfidence = Self.confidence(swedish), enConfidence = Self.confidence(english)
            let picked = enConfidence - svConfidence >= 0.15 ? "english" : "swedish"
            outputs["apple-auto", default: []].append(picked == "english" ? Self.text(english) : Self.text(swedish))
            print(String(format: "VOICE piece %d: sv %.2f en %.2f → %@", index, svConfidence, enConfidence, picked))

            // Your idea: Swedish base; doubtful words (low confidence) heard again in English alone,
            // used when English is confident about them.
            var mixed: [String] = []
            var index = 0
            let spoken = swedish
            while index < spoken.count {
                let word = spoken[index]
                guard word.confidence < 0.35, word.text.contains(where: \.isLetter), word.start >= 0 else {
                    mixed.append(word.text); index += 1; continue
                }
                var end = index
                while end + 1 < spoken.count, spoken[end + 1].confidence < 0.35, spoken[end + 1].start >= 0 { end += 1 }
                let from = max(0, Int((spoken[index].start - 0.15) * 16_000))
                let to = min(piece.count, Int((spoken[end].end + 0.15) * 16_000))
                let again = to > from ? try await Self.words(Array(piece[from..<to]) + [Float](repeating: 0, count: 8_000), .english) : []
                let original = spoken[index...end].map(\.text).joined(separator: " ")
                if !again.isEmpty, Self.confidence(again) >= 0.5 {
                    mixed.append(Self.text(again))
                    print("VOICE   swap \(original) → \(Self.text(again))")
                } else {
                    mixed.append(original)
                }
                index = end + 1
            }
            outputs["apple-sv-swap-english", default: []].append(mixed.joined(separator: " "))
        }
        try FileManager.default.createDirectory(at: Self.out, withIntermediateDirectories: true)
        for (name, texts) in outputs {
            try texts.joined(separator: "\n").write(to: Self.out.appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8)
        }
        await AppleTranscriber.release([.english, .swedish])
    }
}
