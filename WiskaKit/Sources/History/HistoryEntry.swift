import Core
import Foundation
import SwiftData

@Model
final class HistoryEntry {
    var date: Date
    var appBundleID: String?
    var languageRaw: String?
    var engineRaw: String
    var rawText: String
    var finalText: String
    var pasted: Bool
    var duration: Double = 0
    // Added in 1.2: older entries read 0 (not measured).
    var latency: Double = 0
    var transcriptionTime: Double = 0
    var cleanupTime: Double = 0

    init(_ record: DictationRecord) {
        date = record.date
        appBundleID = record.appBundleID
        languageRaw = record.language?.rawValue
        engineRaw = record.engine.rawValue
        rawText = record.rawText
        finalText = record.finalText
        pasted = record.pasted
        duration = record.duration
        latency = record.latency
        transcriptionTime = record.transcriptionTime
        cleanupTime = record.cleanupTime
    }

    var record: DictationRecord {
        DictationRecord(date: date, appBundleID: appBundleID,
                        language: languageRaw.flatMap(Language.init(rawValue:)),
                        engine: SpeechEngine(rawValue: engineRaw) ?? .apple,
                        rawText: rawText, finalText: finalText, pasted: pasted, duration: duration,
                        latency: latency, transcriptionTime: transcriptionTime, cleanupTime: cleanupTime)
    }
}
