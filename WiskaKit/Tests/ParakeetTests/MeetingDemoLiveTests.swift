import Cleanup
import Core
import Dictation
import Foundation
import Testing
@testable import Parakeet

/// A whole business call through the meeting pipeline, as Wiska runs it after you press Stop:
/// your microphone and the call as two tracks, the call's people told apart, Parakeet, then
/// Apple Intelligence's notes. Prints what the Meeting window shows, before and after naming.
/// Opt-in (needs Parakeet installed, Apple Intelligence, and downloads the speaker model):
/// WISKA_DEMO_MEETING=1 swift test --filter MeetingDemoLiveTests
@MainActor
struct MeetingDemoLiveTests {
    struct Line {
        let voice: String
        let text: String
        /// Seconds this line starts before the previous one ends (talking over them).
        var over = 0.0
    }

    static let you = "Daniel"
    static let people = ["Samantha": "Sarah", "Aman": "Raj", "Moira": "Fiona"]

    static let call: [Line] = [
        Line(voice: you, text: "Good morning everyone, thanks for joining. Today we need to agree on the launch date for the new app, and who does what. Sarah, can you start with where development stands?"),
        Line(voice: "Samantha", text: "Sure. The core features are done, but the payment integration still has two open bugs. I expect them fixed by next Wednesday."),
        Line(voice: you, text: "Okay. Is that realistic?"),
        Line(voice: "Samantha", text: "Yes, as long as we don't add anything new before then."),
        Line(voice: "Aman", text: "That works for marketing. We need about three weeks from a fixed date to prepare the campaign, so if development is done on Wednesday, we could launch on November twenty fourth."),
        Line(voice: "Moira", text: "Sorry to jump in. Support also needs the help articles ready before launch. Can we get a test build on Thursday to write them?", over: 0.8),
        Line(voice: "Samantha", text: "I can give you a test build on Thursday morning."),
        Line(voice: "Moira", text: "Great, thanks."),
        Line(voice: you, text: "Then let's decide. We launch on November twenty fourth. Raj, please send the campaign plan by Friday."),
        Line(voice: "Aman", text: "Will do."),
        Line(voice: you, text: "Sarah fixes the payment bugs by Wednesday and sends the test build to Fiona on Thursday. Fiona, please have the help articles ready a week before launch."),
        Line(voice: "Moira", text: "No problem."),
        Line(voice: "Aman", text: "One more thing. The budget for paid ads isn't approved yet. Who signs that off?"),
        Line(voice: you, text: "I'll take that to finance and get back to you by Tuesday."),
        Line(voice: "Aman", text: "Perfect."),
        Line(voice: you, text: "Good. Thanks everyone, talk next week."),
    ]

    @Test(.enabled(if: ProcessInfo.processInfo.environment["WISKA_DEMO_MEETING"] != nil && MeetingNotes.appleAvailable))
    func aBusinessCall() async throws {
        // The two tracks a recording gives: the microphone (you) and the Mac's sound (the call).
        var mine: [Float] = []
        var theirs: [Float] = []
        var end = 0
        for line in Self.call {
            var voice = try SpeakerTuningLiveTests.load(Self.say(line))
            let isMine = line.voice == Self.you
            if !isMine { voice = SpeakerTuningLiveTests.phone(voice) }   // the call is phone quality
            let start = max(0, end + (line.over > 0 ? -Int(line.over * 16_000) : 8_000))
            end = start + voice.count
            for track in [0, 1] where (track == 0) == isMine {
                if track == 0 { mine += [Float](repeating: 0, count: max(0, end - mine.count)) } else {
                    theirs += [Float](repeating: 0, count: max(0, end - theirs.count))
                }
                for offset in voice.indices {
                    if track == 0 { mine[start + offset] += voice[offset] } else { theirs[start + offset] += voice[offset] }
                }
            }
        }
        let length = max(mine.count, theirs.count)
        mine += [Float](repeating: 0, count: length - mine.count)
        theirs += [Float](repeating: 0, count: length - theirs.count)
        // No headphones: the laptop's speakers leak the call into the microphone, a little late.
        for index in 240..<length { mine[index] += theirs[index - 240] * 0.15 }
        print("DEMO call: \(String(format: "%.0f", Double(length) / 16_000)) s, you + \(Self.people.count) on the call")

        var clock = ContinuousClock.now
        let models = FileManager.default.temporaryDirectory.appendingPathComponent("demo-\(UUID())")
            .appendingPathComponent("speaker-diarization-coreml")
        defer { try? FileManager.default.removeItem(at: models.deletingLastPathComponent()) }
        try await DiarizerDownloader().download(to: models, progress: { _ in })
        let voices = try await SpeakerDiarizer.segments(in: theirs, speakers: Self.people.count, directory: models)
            .map { VoiceSegment(speaker: $0.speaker, start: $0.start, end: $0.end) }
        let turns = MeetingTranscription.turns(from: voices, sampleCount: theirs.count, audio: theirs)
        print("DIARIZATION", voices.map { "\($0.speaker) \(String(format: "%.1f–%.1f", $0.start, $0.end))" })
        print("DEMO speakers: \(Set(voices.map(\.speaker)).count) voices, \(turns.count) turns, \(ContinuousClock.now - clock)")

        clock = .now
        let parakeet = ParakeetTranscriber(store: ParakeetModelStore())
        try await parakeet.prepare()
        let segments = try await MeetingTranscription.run(you: mine, others: theirs, othersTurns: turns,
                                                          session: { _ in try await parakeet.makeSession(language: .fixed(.english)) },
                                                          progress: { _ in })
        print("DEMO transcribed: \(ContinuousClock.now - clock)")

        clock = .now
        let notes = try await MeetingNotes.write(MeetingTranscription.transcript(segments), language: .english,
                                                 generate: MeetingNotes.apple, progress: { _ in })
        print("DEMO notes: \(ContinuousClock.now - clock)")

        // The window's "Who's who?" rows; then the names, as you'd type them.
        var names: [Speaker: String] = [:]
        print("\nWHO'S WHO")
        for sample in MeetingTranscription.samples(segments) {
            print("  \(sample.speaker.displayName)  [ name ]  “\(sample.line)”")
            names[sample.speaker] = Self.whoSaid(sample.line)
        }
        let window = { (names: [Speaker: String]) in
            "Notes\n\n\(MeetingTranscription.rename(notes, names: names))\n\nTranscript\n\n\(MeetingTranscription.transcript(segments, names: names))"
        }
        print("\nBEFORE NAMING>>>\n\(window([:]))\n<<<")
        print("\nNAMED \(names.map { "\($0.key.displayName) = \($0.value)" }.sorted().joined(separator: ", "))")
        print("AFTER NAMING>>>\n\(window(names))\n<<<")
        #expect(segments.contains { $0.speaker == .you })
        #expect(!notes.isEmpty)
    }

    /// Whose line this is, by the most words shared with the script (stands in for you naming them).
    static func whoSaid(_ text: String) -> String {
        func words(_ string: String) -> Set<String> {
            Set(string.lowercased().split { !$0.isLetter }.map(String.init))
        }
        let heard = words(text)
        let best = call.filter { $0.voice != you }.max { words($0.text).intersection(heard).count < words($1.text).intersection(heard).count }
        return best.flatMap { people[$0.voice] } ?? "?"
    }

    static func say(_ line: Line) throws -> URL {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("demo-line-\(UUID()).aiff")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", line.voice, "-o", file.path, line.text]
        try say.run()
        say.waitUntilExit()
        return file
    }
}
