import AVFoundation
import FluidAudio
import Foundation
import Testing
@testable import Parakeet

/// Compares speaker-diarization pipelines and settings on generated conversations (macOS voices,
/// some at phone quality, some talking over each other), scored by diarization error rate.
/// Opt-in, downloads the models: WISKA_LIVE_TUNING=1 swift test --filter SpeakerTuningLiveTests
struct SpeakerTuningLiveTests {
    struct Line { let voice: String; let text: String }
    struct Conversation { let name: String; let lines: [Line]; var overlap = 0.0; var phone = false }

    static let script = [
        "Let's go through the budget for next quarter, starting with travel.",
        "Sure.",
        "The conference costs went up by about twenty percent compared to last year.",
        "That's more than we planned for. Can we cut anything?",
        "Yes.",
        "We could send two people instead of four, and book the hotel earlier.",
        "Okay, sounds good.",
        "I'll also ask the vendor for a discount on the booth.",
        "Right. When do you need an answer?",
        "By Friday, so we can sign before the price changes.",
        "Fine. Anything else on travel?",
        "No, that's it.",
    ]

    static func conversation(_ name: String, _ voices: [String], overlap: Double = 0, phone: Bool = false) -> Conversation {
        // Turns go round the voices, with an occasional repeat so it isn't a strict rotation.
        let order = script.indices.map { $0 % 5 == 4 ? ($0 + 1) % voices.count : $0 % voices.count }
        return Conversation(name: name, lines: zip(order, script).map { Line(voice: voices[$0], text: $1) },
                            overlap: overlap, phone: phone)
    }

    static let conversations: [Conversation] = [
        conversation("2 people, man and woman", ["Daniel", "Samantha"]),
        conversation("2 women", ["Samantha", "Karen"]),
        conversation("2 men", ["Fred", "Ralph"]),
        conversation("3 people", ["Daniel", "Samantha", "Fred"]),
        conversation("4 people", ["Daniel", "Samantha", "Fred", "Karen"]),
        conversation("2 people, talking over", ["Daniel", "Samantha"], overlap: 0.7),
        conversation("3 people, phone", ["Daniel", "Samantha", "Fred"], phone: true),
        conversation("4 people, phone, talking over", ["Daniel", "Samantha", "Fred", "Moira"], overlap: 0.5, phone: true),
    ]

    enum Setting: CustomStringConvertible {
        case legacy(Float)
        case offline(threshold: Double, hint: Bool)
        var description: String {
            switch self {
            case .legacy(let threshold): "legacy \(threshold)"
            case .offline(let threshold, let hint): "offline \(threshold)\(hint ? " + count" : "")"
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["WISKA_LIVE_TUNING"] != nil))
    func compareSettings() async throws {
        let models = FileManager.default.temporaryDirectory.appendingPathComponent("tuning-\(UUID())")
        let legacy = try await DiarizerModels.download(to: models.appendingPathComponent("legacy"))
        let offline = try await OfflineDiarizerModels.load(from: models.appendingPathComponent("offline"))

        let settings: [Setting] = [.legacy(0.6), .legacy(0.7),
                                   .offline(threshold: 0.3, hint: false), .offline(threshold: 0.4, hint: false),
                                   .offline(threshold: 0.6, hint: false), .offline(threshold: 0.6, hint: true)]
        var totals = [String: (der: Double, rightCount: Int)]()
        for conversation in Self.conversations {
            let (samples, reference) = try Self.render(conversation)
            let people = Set(reference.map(\.speaker)).count
            for setting in settings {
                let found: [DERSpeakerSegment]
                switch setting {
                case .legacy(let threshold):
                    let manager = DiarizerManager(config: DiarizerConfig(clusteringThreshold: threshold))
                    manager.initialize(models: legacy)
                    found = try manager.performCompleteDiarization(samples).segments
                        .map { DERSpeakerSegment(speaker: $0.speakerId, start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds)) }
                case .offline(let threshold, let hint):
                    var config = OfflineDiarizerConfig()
                    config.clustering.threshold = threshold
                    if hint { config.clustering.numSpeakers = people }
                    let manager = OfflineDiarizerManager(config: config)
                    manager.initialize(models: offline)
                    found = try await manager.process(audio: samples).segments
                        .map { DERSpeakerSegment(speaker: $0.speakerId, start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds)) }
                }
                let score = DiarizationDER.compute(ref: reference, hyp: found, collar: 0.25)
                let speakers = Set(found.map(\.speaker)).count
                print(String(format: "RESULT %-32@ %-20@ DER %5.1f%%  speakers %d/%d",
                             conversation.name as NSString, setting.description as NSString,
                             score.der * 100, speakers, people))
                let total = totals[setting.description] ?? (0, 0)
                totals[setting.description] = (total.der + score.der, total.rightCount + (speakers == people ? 1 : 0))
            }
        }
        for setting in settings {
            let total = totals[setting.description]!
            let count = Double(Self.conversations.count)
            print(String(format: "AVERAGE %-20@ DER %5.1f%%  right count %d/%d",
                         setting.description as NSString, total.der / count * 100, total.rightCount, Self.conversations.count))
        }
        try? FileManager.default.removeItem(at: models)
    }

    /// The conversation as 16 kHz mono, with who spoke when.
    static func render(_ conversation: Conversation) throws -> ([Float], [DERSpeakerSegment]) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tuning-voices-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var samples: [Float] = []
        var reference: [DERSpeakerSegment] = []
        for (index, line) in conversation.lines.enumerated() {
            let file = folder.appendingPathComponent("\(index).aiff")
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["-v", line.voice, "-o", file.path, line.text]
            try say.run()
            say.waitUntilExit()
            var voice = try load(file)
            if conversation.phone { voice = phone(voice) }
            let gap = index == 0 ? 0 : (conversation.overlap > 0 ? -Int(conversation.overlap * 16_000) : 8_000)
            let start = max(0, samples.count + gap)
            samples += [Float](repeating: 0, count: max(0, start + voice.count - samples.count))
            for offset in voice.indices { samples[start + offset] += voice[offset] }
            reference.append(DERSpeakerSegment(speaker: line.voice, start: Double(start) / 16_000,
                                               end: Double(start + voice.count) / 16_000))
        }
        return (samples, reference)
    }

    /// Roughly what a call does to a voice: 8 kHz bandwidth and a little noise.
    static func phone(_ samples: [Float]) -> [Float] {
        var generator = SystemRandomNumberGenerator()
        var narrow = samples
        for index in 2..<samples.count { narrow[index] = (samples[index] + 2 * samples[index - 1] + samples[index - 2]) / 4 }
        return narrow.map { $0 + Float.random(in: -0.003...0.003, using: &generator) }
    }

    static func load(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let converter = AVAudioConverter(from: file.processingFormat, to: output)!
        let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: input)
        let result = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: AVAudioFrameCount(Double(file.length) * 16_000 / file.processingFormat.sampleRate) + 1_024)!
        var given = false
        _ = converter.convert(to: result, error: nil) { _, status in
            if given { status.pointee = .endOfStream; return nil }
            given = true
            status.pointee = .haveData
            return input
        }
        return Array(UnsafeBufferPointer(start: result.floatChannelData![0], count: Int(result.frameLength)))
    }
}
