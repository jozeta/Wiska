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

    init(_ record: DictationRecord) {
        date = record.date
        appBundleID = record.appBundleID
        languageRaw = record.language?.rawValue
        engineRaw = record.engine.rawValue
        rawText = record.rawText
        finalText = record.finalText
        pasted = record.pasted
        duration = record.duration
    }

    var record: DictationRecord {
        DictationRecord(date: date, appBundleID: appBundleID,
                        language: languageRaw.flatMap(Language.init(rawValue:)),
                        engine: SpeechEngine(rawValue: engineRaw) ?? .apple,
                        rawText: rawText, finalText: finalText, pasted: pasted, duration: duration)
    }
}
