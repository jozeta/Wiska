import AVFoundation
import Core
import Foundation
import Testing
@testable import KBWhisper

/// KB-Whisper on macOS's Swedish voice. `WISKA_REAL_MODEL=1 swift test --filter KBWhisperRealTests`
/// (or through xcodebuild with TEST_RUNNER_WISKA_REAL_MODEL=1). Needs the downloaded model.
@MainActor
struct KBWhisperRealTests {
    nonisolated static var enabled: Bool { ProcessInfo.processInfo.environment["WISKA_REAL_MODEL"] == "1" }

    static func spoken(_ text: String, voice: String) throws -> [Float] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wiska-\(UUID().uuidString).aiff")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", voice, "-o", url.path, text]
        try say.run()
        say.waitUntilExit()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                   frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        return try PCMConverter(from: file.processingFormat, to: .speech16kMono).convert(buffer).floatSamples
    }

    @Test(.enabled(if: enabled), .timeLimit(.minutes(5)))
    func transcribesSwedish() async throws {
        let recognizer = KBWhisperRecognizer(store: KBWhisperModelStore())
        #expect(recognizer.isReady)
        let samples = try Self.spoken("Jag har ett stort hus och en liten trädgård.", voice: "Alva")
        let start = ContinuousClock.now
        let text = try await recognizer.transcribe(samples, language: .swedish)
        print("KB:", text.debugDescription, ContinuousClock.now - start)
        #expect(text.lowercased().contains("ett stort hus"), "\(text)")
        // Loaded now: the time a dictation sees after the fn press has loaded the model.
        let warmStart = ContinuousClock.now
        let again = try await recognizer.transcribe(samples, language: .swedish)
        print("KB warm:", again.debugDescription, ContinuousClock.now - warmStart)
    }
}

/// Swedish with English IT words, read by the Swedish voice: KB-Whisper with and without a
/// prompt. `WISKA_REAL_MODEL=1 swift test --filter SwedishITTermsTests`
@MainActor
struct SwedishITTermsTests {
    static let sentences = [
        "Jag ska deploya den nya releasen till produktion efter att pull requesten har mergats.",
        "Vi har en bugg i backend, API:et returnerar fel när användaren loggar in med single sign-on.",
        "Kan du skapa en ticket i Jira och lägga den i nästa sprint?",
        "Servern i Azure behöver mer minne, så vi skalar upp Kubernetes-klustret.",
        "Jag pushade en fix till main-branchen, men pipelinen i GitHub Actions failade.",
        "Vi kör ett standup varje morgon och en retro efter varje sprint.",
        "Kolla loggarna i Datadog, det ser ut som en timeout mot databasen.",
        "Jag har ett stort hus och en liten trädgård.",
    ]

    static let prompts: [(String, String?)] = [
        ("none", nil),
        ("IT words", "Vi pratar om deploy, release, pull request, merge, branch, commit, backend, frontend, API, server, databas, Kubernetes, Azure, Jira, ticket, sprint, pipeline och bugg."),
        ("style", "Hej! Jag pushade en fix till main i går, men pipelinen failade. Kan du kolla pull requesten och deploya releasen?"),
    ]

    static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    static func errors(_ reference: [String], _ heard: [String]) -> Int {
        var row = Array(0...heard.count)
        for (i, word) in reference.enumerated() {
            var next = [i + 1]
            for (j, other) in heard.enumerated() {
                next.append(min(row[j + 1] + 1, next[j] + 1, row[j] + (word == other ? 0 : 1)))
            }
            row = next
        }
        return row[heard.count]
    }

    @Test(.enabled(if: KBWhisperRealTests.enabled), .timeLimit(.minutes(10)))
    func promptsCompared() async throws {
        let recognizer = KBWhisperRecognizer(store: KBWhisperModelStore())
        #expect(recognizer.isReady)
        var totals = [String: (errors: Int, words: Int)]()
        for sentence in Self.sentences {
            let samples = try KBWhisperRealTests.spoken(sentence, voice: "Alva")
            for (name, prompt) in Self.prompts {
                let text = try await recognizer.transcribe(samples, language: .swedish, prompt: prompt)
                let wrong = Self.errors(Self.words(sentence), Self.words(text))
                print("IT \(name.padding(toLength: 8, withPad: " ", startingAt: 0)) \(wrong) | \(text)")
                let total = totals[name] ?? (0, 0)
                totals[name] = (total.errors + wrong, total.words + Self.words(sentence).count)
            }
        }
        for (name, _) in Self.prompts {
            let total = totals[name]!
            print("IT TOTAL \(name): \(total.errors) wrong words of \(total.words)")
        }
    }
}

/// KB-Whisper on a real recording, in ~10 s pieces, with and without the IT prompt; written to
/// WISKA_VOICE_OUT/kb*.txt. `WISKA_VOICE_FILE=… WISKA_VOICE_OUT=… swift test --filter KBVoiceFileTests`
@MainActor
struct KBVoiceFileTests {
    nonisolated static var file: String? { ProcessInfo.processInfo.environment["WISKA_VOICE_FILE"] }

    @Test(.enabled(if: file != nil), .timeLimit(.minutes(20)))
    func variants() async throws {
        let url = URL(fileURLWithPath: Self.file!)
        let source = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: AVAudioFrameCount(source.length))!
        try source.read(into: buffer)
        let audio = try PCMConverter(from: source.processingFormat, to: .speech16kMono).convert(buffer).floatSamples
        // Same cuts as VoiceFileTests.
        var cuts = [0]
        var target = 160_000
        while target + 48_000 < audio.count {
            var best = target, quietest = Float.greatestFiniteMagnitude
            for start in stride(from: target - 48_000, through: target + 48_000 - 1_600, by: 800) {
                let energy = audio[start..<start + 1_600].reduce(0) { $0 + $1 * $1 }
                if energy < quietest { quietest = energy; best = start + 800 }
            }
            cuts.append(best)
            target = best + 160_000
        }
        cuts.append(audio.count)
        let recognizer = KBWhisperRecognizer(store: KBWhisperModelStore())
        #expect(recognizer.isReady)
        let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["WISKA_VOICE_OUT"] ?? NSTemporaryDirectory())
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for (name, prompt) in SwedishITTermsTests.prompts {
            var texts: [String] = []
            for (from, to) in zip(cuts, cuts.dropFirst()) {
                texts.append(try await recognizer.transcribe(Array(audio[from..<to]), language: .swedish, prompt: prompt))
            }
            try texts.joined(separator: "\n").write(to: out.appendingPathComponent("kb-\(name.replacingOccurrences(of: " ", with: "-")).txt"),
                                                    atomically: true, encoding: .utf8)
        }
    }
}
