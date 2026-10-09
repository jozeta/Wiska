import Core
import Preferences
import SwiftUI

/// Short instructions and examples, inside Settings.
struct HelpTab: View {
    let model: AppModel

    var body: some View {
        let languages = model.settings.enabledLanguages
        Form {
            Section("Getting started") {
                tip("Hold fn, speak, release", "The text appears where your cursor is. Release a moment after your last word.")
                tip("First time", "Grant Microphone and Accessibility in the Setup window (General → Open Setup…).")
            }
            Section("Dictating") {
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
            Section("Snippets") {
                tip("When I say … → Insert …", "In the Snippets tab, save a phrase (“insert my signature”) and the text it stands for. Say the phrase anywhere in a dictation and the text is inserted exactly as written.")
                tip("Example", "“thanks for the help, insert my signature” → the sentence, then your signature on its own lines.")
                tip("Check without dictating", "Type a sentence in Snippets → Try it to see what would be inserted.")
                ForEach(model.snippetStore.snippets.filter { $0.problems.isEmpty }) { snippet in
                    LabeledContent("“\(snippet.spokenPhrases.joined(separator: "” or “"))”",
                                   value: snippet.text.components(separatedBy: "\n").first ?? "")
                }
            }
            Section("Styles") {
                tip("Per kind of app", "Messages and work chat are Casual, email is Formal, terminals and editors get exactly what you say. Change it in Cleanup → Styles.")
                tip("Numbers", "“three thirty” becomes 3:30, “twenty five percent” becomes 25%.")
            }
            Section("Troubleshooting") {
                tip("fn opens the emoji picker", "System Settings → Keyboard → “Press 🌐 key to” → Do Nothing.")
                tip("Nothing is typed", "Check Accessibility in System Settings → Privacy & Security, or switch After dictation to Copy to clipboard only.")
                tip("No cleanup or editing", "Cleanup and editing need Apple Intelligence (System Settings → Apple Intelligence & Siri).")
                tip("Wrong words", "Add names and terms in the Dictionary tab.")
            }
        }
        .formStyle(.grouped)
        .frame(height: 520)   // scrolls instead of stretching the Settings window
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
