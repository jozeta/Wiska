import Core
import Preferences
import SwiftUI

/// Short instructions and examples, inside Settings.
struct HelpTab: View {
    let model: AppModel
    @State private var diagnostics = DiagnosticsState.idle

    enum DiagnosticsState { case idle, collecting, copied, failed }

    var body: some View {
        let languages = model.settings.enabledLanguages
        Form {
            Section("Getting started") {
                tip("Hold fn, speak, release", "The text appears where your cursor is. Release a moment after your last word.")
                tip("First time", "Grant Microphone and Accessibility in the Setup window (General → Open Setup…).")
            }
            Section("Dictating") {
                tip("Swedish", "Download KB-Whisper in Settings → Models and switch it on in Speech: Swedish dictations are re-transcribed by the National Library of Sweden's model for fewer mishearings. Compare on my voice shows how each engine does with your voice.")
                tip("Hands-free", "Double-tap fn, speak as long as you like, tap fn to finish. Esc cancels.")
                tip("Another language", "Hold fn+⇧ for your second language, or let Auto-detect choose (Settings → Languages).")
                tip("Live preview", "Your words scroll under the waveform while you speak (Apple engine).")
            }
            Section("Voice commands") {
                ForEach(languages, id: \.self) { language in
                    let rules = language.rules
                    LabeledContent("\(language.flag) \(language.displayName)") {
                        Text("“\(rules.newLine[0])” · “\(rules.newParagraph[0])” · “\(rules.scratchThat[0])”")
                            .foregroundStyle(.secondary)
                    }
                }
                Text("New line, new paragraph, and remove what you just said.")
                    .font(.caption).foregroundStyle(.secondary)
                tip("Lists", "Pause between items: “first eggs, second milk, third bread” becomes a numbered list.")
            }
            Section("Editing selected text") {
                tip("Select, hold fn+⌃, say what to change", "Wiska rewrites the selection on your Mac and replaces it. ⌘Z undoes it.")
                ForEach(Self.editExamples, id: \.self) { example in
                    Label(example, systemImage: "text.cursor").foregroundStyle(.secondary)
                }
            }
            Section("Writing and saved commands") {
                tip("Write with nothing selected", "Click where the text should go, hold fn+⌃ and say what to write — “reply that I'll be there at three”. Wiska reads the text around the cursor on your Mac (never stored) and writes in its language. ⌘Z removes it.")
                tip("Saved commands", "Say a command's phrase — “formal” — and Wiska uses its instruction. Add more after a comma or “and”: “formal and a bit shorter”. A sentence that just starts with the word (“fix the second sentence”) is used as you said it. Set them up in the Commands tab.")
                ForEach(model.commandStore.commands.filter { $0.problems.isEmpty }) { command in
                    LabeledContent("“\(command.spokenPhrases.joined(separator: "” or “"))”", value: command.instruction)
                }
            }
            Section("Snippets") {
                Text("Save a phrase and the text it stands for in the Snippets tab. Say the phrase anywhere in a dictation, and the text is inserted exactly as you wrote it — in any app, line breaks included.")
                tip("Example", "When I say “insert my signature” → Insert “Best regards, Johan”. Dictating “thanks for the help, insert my signature” gives the sentence, then your signature on its own lines.")
                tip("Choosing a phrase", "Use words you wouldn't say by accident, like “insert my …”. Capitals, punctuation and a slightly misheard word don't matter.")
                tip("Another language", "Add a second phrase to the same snippet, like “infoga min signatur”.")
                tip("Check without dictating", "Type a sentence in Snippets → Try it to see what would be inserted.")
                ForEach(model.snippetStore.snippets.filter { $0.problems.isEmpty }) { snippet in
                    LabeledContent("“\(snippet.spokenPhrases.joined(separator: "” or “"))”",
                                   value: snippet.text.components(separatedBy: "\n").first ?? "")
                }
            }
            Section("Styles") {
                tip("Grammar", "With Fix grammar on (Settings → Cleanup), “I has a apple” becomes “I have an apple”. Gemma, downloaded in Settings → Models, is best at it, especially in Swedish.")
                tip("Per kind of app", "Messages and work chat are Casual, email is Formal, terminals and editors get exactly what you say. Change it in Cleanup → Styles.")
                tip("Numbers", "“three thirty” becomes 3:30, “twenty five percent” becomes 25%.")
            }
            Section("Troubleshooting") {
                tip("fn opens the emoji picker", "System Settings → Keyboard → “Press 🌐 key to” → Do Nothing.")
                tip("Nothing is typed", "Check Accessibility in System Settings → Privacy & Security, or switch After dictation to Copy to clipboard only.")
                tip("No cleanup or editing", "Cleanup and editing need Apple Intelligence (System Settings → Apple Intelligence & Siri) or the Gemma model (download it in Settings → Models, choose it in Cleanup).")
                tip("Wrong words", "Add names and terms in the Dictionary tab.")
            }
            Section("Reporting a problem") {
                HStack {
                    Button("Copy diagnostics") {
                        diagnostics = .collecting
                        Task { diagnostics = await model.copyDiagnostics() ? .copied : .failed }
                    }
                    .disabled(diagnostics == .collecting)
                    switch diagnostics {
                    case .idle: EmptyView()
                    case .collecting: ProgressView().controlSize(.small)
                    case .copied: Label("Copied — paste it into your report", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failed: Text("Couldn't read the log").foregroundStyle(.red)
                    }
                }
                Text("Puts Wiska's version, your settings and what it logged since it started on the clipboard. It has word counts, timings and error types — never what you said or the text you were working in.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    static let editExamples = [
        "“make this more formal”",
        "“translate to Swedish”",
        "“make it shorter”",
        "“fix the grammar”",
        "“turn this into a bulleted list”",
        "“make it sound friendlier”",
    ]

    private func tip(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}
