import Foundation
import Testing
@testable import Cleanup

/// Can the language model put back English IT terms a Swedish recogniser mangled?
/// Opt-in: WISKA_LIVE_NOTES=1 swift test --filter SwedishITRepairLiveTests
@MainActor
struct SwedishITRepairLiveTests {
    static let instructions = """
    You correct a Swedish dictation by someone who works in IT. Swedish speech recognition sometimes mishears \
    the English technical terms they mix in. If a word is clearly a misheard IT term, write the term correctly \
    and keep its Swedish ending ("pull requesten", "Kubernetes-klustret"). Terms they use include: deploy, \
    pipeline, pull request, merge, branch, code review, staging, deprecated, endpoint, frontend, backend, API, \
    Jira, Kubernetes, Redis, Datadog, AWS, Azure AD, Elasticsearch, Slack, GitHub Actions. \
    Leave everything else exactly as it is: correct English terms stay English, Swedish words stay Swedish, \
    no rewording. If nothing needs fixing, return the text unchanged. Reply with the text only.
    """

    static let heard = [
        "Jag ska deplåja den nya releasen till produktion efter att pulverquasten har märjats.",
        "Vi har en boogie back-end, AP1 returnerar fel när användaren loggar in med single signum.",
        "Kan du skapa en ticket i Gira och lägga den i nästa sprint?",
        "Serveniasuri behöver mer minne, så vi skalar upp kubenetesklustret.",
        "Ja Puss hade en fix till main-branschen, men pippelinen i J2 Beck-chains failade.",
        "Jag ska ploga den nya releasen till produktion efter att Fullen har mejats",
        "Kolla lågan i datalog. Det ser ut som en tao mot databasen.",
        "Vi kör ett ständigt varje morgon och en retro efter varje sprint",
        "Jag har en stort hus och en liten trädgård",
        "Vi ska ploga åkern i morgon och sedan äter vi middag hos Malin.",
    ]

    @Test(.enabled(if: ProcessInfo.processInfo.environment["WISKA_LIVE_NOTES"] != nil && MeetingNotes.appleAvailable))
    func appleRepairsTerms() async throws {
        for text in Self.heard {
            let fixed = try await MeetingNotes.apple(Self.instructions, text)
            print("REPAIR \(text)\n    →  \(fixed)")
        }
    }

    /// Each line of a real recording's transcript (WISKA_REPAIR_FILE), repaired.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WISKA_REPAIR_FILE"] != nil && MeetingNotes.appleAvailable))
    func appleRepairsRecording() async throws {
        let path = ProcessInfo.processInfo.environment["WISKA_REPAIR_FILE"]!
        for line in try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n") {
            let fixed = try await MeetingNotes.apple(Self.instructions, String(line))
            print("REPAIR \(line)\n    →  \(fixed)")
        }
    }
}
