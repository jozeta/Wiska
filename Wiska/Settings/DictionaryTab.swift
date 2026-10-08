import Preferences
import SwiftUI

struct DictionaryTab: View {
    let store: DictionaryStore
    @State private var newWord = ""
    @State private var heard = ""
    @State private var written = ""

    var body: some View {
        Form {
            Section("Dictionary") {
                Text("Names and terms you use. Words also help Swedish recognition; replacements fix anything that's consistently misheard.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array(store.dictionary.words.enumerated()), id: \.offset) { index, word in
                    HStack {
                        Text(word)
                        Spacer()
                        Button(role: .destructive) { store.removeWords(at: IndexSet(integer: index)) } label: {
                            Image(systemName: "minus.circle")
                        }.buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("Add word (e.g. Kvarnholmen)", text: $newWord)
                        .onSubmit(addWord)
                    Button("Add", action: addWord).disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ForEach(store.dictionary.replacements) { replacement in
                    HStack {
                        Text("“\(replacement.heard)” → \(replacement.written)")
                        Spacer()
                        Button(role: .destructive) { store.removeReplacement(id: replacement.id) } label: {
                            Image(systemName: "minus.circle")
                        }.buttonStyle(.borderless)
                    }
                }
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
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func addWord() {
        store.addWord(newWord)
        newWord = ""
    }
}
