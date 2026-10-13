import Core
import Preferences
import SwiftUI

struct DictionaryTab: View {
    let store: DictionaryStore
    let model: AppModel
    @State private var newWord = ""
    @State private var heard = ""
    @State private var written = ""

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            if settings.learnFromCorrections && !model.corrections.pending.isEmpty {
                Section("Suggested from your corrections") {
                    ForEach(model.corrections.pending) { suggestion in
                        HStack {
                            Text("“\(suggestion.correction.heard)” → \(suggestion.correction.written)")
                            if suggestion.count > 1 {
                                Text("\(suggestion.count)×").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Add") { model.acceptCorrection(suggestion.correction) }
                            Button("Dismiss") { model.corrections.dismiss(suggestion.correction) }
                        }
                    }
                    Text("You fixed these right after dictating them. Add one and Wiska writes it your way from now on.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Dictionary") {
                Text("Names and terms you use. Words also help Swedish recognition; replacements fix anything that's consistently misheard.")
                    .font(.caption).foregroundStyle(.secondary)
                // Lists scroll inside a fixed height so the add rows below stay on screen.
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(store.dictionary.words.enumerated()), id: \.offset) { index, word in
                            HStack {
                                Text(word)
                                Spacer()
                                Button(role: .destructive) { store.removeWords(at: IndexSet(integer: index)) } label: {
                                    Image(systemName: "minus.circle")
                                }.buttonStyle(.borderless)
                            }
                        }
                    }
                }
                .frame(maxHeight: 160)
                HStack {
                    TextField("Add word (e.g. Kvarnholmen)", text: $newWord)
                        .onSubmit(addWord)
                    Button("Add", action: addWord).disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(store.dictionary.replacements) { replacement in
                            HStack {
                                Text("“\(replacement.heard)” → \(replacement.written)")
                                Spacer()
                                Button(role: .destructive) { store.removeReplacement(id: replacement.id) } label: {
                                    Image(systemName: "minus.circle")
                                }.buttonStyle(.borderless)
                            }
                        }
                    }
                }
                .frame(maxHeight: 120)
                HStack {
                    TextField("Heard", text: $heard)
                    TextField("Write as", text: $written)
                    Button("Add") {
                        store.addReplacement(heard: heard, written: written)
                        heard = ""
                        written = ""
                    }
                    .disabled(heard.trimmingCharacters(in: .whitespaces).isEmpty
                              || written.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section("Learning") {
                Toggle("Suggest words from my corrections", isOn: $settings.learnFromCorrections)
                Text("For a minute after a dictation, Wiska notices when you fix a misheard name or term in what it just typed, and suggests it here. The text is read on this Mac and never kept — only the corrected word pair is.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func addWord() {
        store.addWord(newWord)
        newWord = ""
    }
}
