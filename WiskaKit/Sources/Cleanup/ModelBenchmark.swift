import Core
import Foundation

/// One check in Settings → Cleanup → Compare models.
public struct BenchmarkCase: Identifiable, Sendable {
    public enum Kind: Sendable {
        case cleanup(CleanupLevel)
        case edit(text: String)
        case write(context: String)
    }

    public let id: Int
    public let title: String
    public let kind: Kind
    /// The dictation (cleanup) or the instruction (edit, write).
    public let input: String
    public let language: Language?
    /// Each item must appear; "a|b" means either. Words are matched as words, symbols as text.
    public let mustContain: [String]
    public let mustNotContain: [String]
    public let minBullets: Int

    init(_ id: Int, _ title: String, _ kind: Kind, _ input: String, _ language: Language?,
         contains: [String] = [], not: [String] = [], minBullets: Int = 0) {
        self.id = id
        self.title = title
        self.kind = kind
        self.input = input
        self.language = language
        mustContain = contains
        mustNotContain = not
        self.minBullets = minBullets
    }

    public func passes(_ output: String) -> Bool {
        mustContain.allSatisfy { item in item.split(separator: "|").contains { Self.found(String($0), in: output) } }
            && !mustNotContain.contains { Self.found($0, in: output) }
            && Self.bullets(in: output) >= minBullets
    }

    static func found(_ needle: String, in output: String) -> Bool {
        let words = PhraseMatcher.bareWords(needle)
        guard !words.isEmpty else { return output.contains(needle) }   // "?", ">>>"
        let haystack = PhraseMatcher.bareWords(output)
        guard haystack.count >= words.count else { return false }
        return (0...(haystack.count - words.count)).contains { Array(haystack[$0..<$0 + words.count]) == words }
    }

    static func bullets(in output: String) -> Int {
        output.components(separatedBy: .newlines).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("- ") || trimmed.hasPrefix("• ") || trimmed.hasPrefix("* ")
                || trimmed.range(of: #"^\d+[.)] "#, options: .regularExpression) != nil
        }.count
    }
}

public struct BenchmarkResult: Sendable {
    public let caseID: Int
    public let output: String
    public let passed: Bool
    public let duration: Duration
}

/// The same sentences through any model: grammar, cleanup, edits and writing (spec §4).
@MainActor
public enum ModelBenchmark {
    public static let cases: [BenchmarkCase] = [
        .init(1, "Grammar · English", .cleanup(.light), "He go to the store yesterday and buyed some milk.", .english,
              contains: ["went", "bought"], not: ["buyed"]),
        .init(2, "Grammar · English", .cleanup(.light), "I has a apple. Their going to the park.", .english,
              contains: ["have an apple", "They're|They are"], not: ["I has"]),
        .init(3, "Grammar · English", .cleanup(.light), "She don't like it, its to late.", .english,
              contains: ["doesn't|does not", "too late"], not: ["don't like"]),
        .init(4, "Grammar · Swedish", .cleanup(.light), "Jag har en stort hus och hon gillar honom bil.", .swedish,
              contains: ["ett stort hus", "hans bil"], not: ["honom bil"]),
        .init(5, "Grammar · Swedish", .cleanup(.light), "Vi ska köpa en äpple imorgon.", .swedish,
              contains: ["ett äpple"], not: ["en äpple"]),
        .init(6, "Grammar · Swedish", .cleanup(.light), "Han har inte ätit något mat idag.", .swedish,
              contains: ["någon mat"], not: ["något mat"]),
        .init(7, "Grammar · German", .cleanup(.light), "Ich habe ein großer Hund und er sind sehr nett.", .german,
              contains: ["einen großen Hund", "ist"], not: ["er sind"]),
        .init(8, "Cleanup · English", .cleanup(.polished), "um so I think we should uh meet on Tuesday no wait Wednesday", .english,
              contains: ["Wednesday"], not: ["um", "Tuesday"]),
        .init(9, "Cleanup · Swedish", .cleanup(.polished), "eh jag tror att vi ska ses på tisdag nej förresten onsdag", .swedish,
              contains: ["onsdag"], not: ["eh", "tisdag"]),
        .init(10, "Question stays a question", .cleanup(.polished), "can you send me the report by Friday", .english,
              contains: ["?"]),
        .init(11, "Edit · formal", .edit(text: "hey can u send it asap"), "make this more formal", .english,
              not: ["u", "asap"]),
        .init(12, "Edit · translate", .edit(text: "Vi ses imorgon klockan tre."), "translate to English", .swedish,
              contains: ["tomorrow"], not: ["imorgon"]),
        .init(13, "Edit · list", .edit(text: "milk eggs bread"), "turn it into a bulleted list", .english,
              minBullets: 3),
        .init(14, "Write · reply", .write(context: "Hi Johan,\n\nAre you coming tomorrow? It starts at three.\n\nAnna\n\n[cursor]"),
              "reply that I'll be there", .english, contains: ["there"], not: ["Are you coming", ">>>"]),
        .init(15, "Write · Swedish reply", .write(context: "Hej Johan,\n\nKommer du på mötet imorgon?\n\nAnna\n\n[cursor]"),
              "svara att jag kommer", .swedish, contains: ["kommer"], not: ["Kommer du på mötet"]),
    ]

    public static func run(_ benchmarkCase: BenchmarkCase, rewriter: any TextRewriter,
                           editor: any TextEditor) async -> BenchmarkResult {
        let start = ContinuousClock.now
        let output: String
        do {
            switch benchmarkCase.kind {
            case .cleanup(let level):
                output = try await rewriter.rewrite(benchmarkCase.input, level: level, language: benchmarkCase.language,
                                                    style: .formal, grammar: true)
            case .edit(let text):
                output = try await editor.edit(text, instruction: benchmarkCase.input, language: benchmarkCase.language)
            case .write(let context):
                output = try await editor.write(instruction: benchmarkCase.input, context: context,
                                                language: benchmarkCase.language)
            }
        } catch {
            return BenchmarkResult(caseID: benchmarkCase.id, output: "Error: \(error)", passed: false,
                                   duration: ContinuousClock.now - start)
        }
        return BenchmarkResult(caseID: benchmarkCase.id, output: output, passed: benchmarkCase.passes(output),
                               duration: ContinuousClock.now - start)
    }
}
