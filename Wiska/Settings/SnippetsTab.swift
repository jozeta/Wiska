import Cleanup
import Core
import Preferences
import SwiftUI

/// Saved texts inserted by voice: "When I say <phrase> → Insert <text>".
struct SnippetsTab: View {
    let store: SnippetStore
    @State private var trial = ""

    var body: some View {
        Form {
            Section {
                Text("Say a snippet's phrase anywhere in a dictation to insert its text. How it works and examples: Help tab.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Try it") {
                TextField("Try it", text: $trial, prompt: Text("Type what you would say, e.g. “thanks, insert my signature”"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                if !trial.isEmpty {
                    let result = SnippetPreview.expand(trial, snippets: store.snippets)
                    if result == trial {
                        Text("No snippet phrase in this sentence — it would be typed as you said it.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Wiska would insert:").font(.caption).foregroundStyle(.secondary)
                            Text(result).textSelection(.enabled)
                        }
                    }
                }
            }

            Section("Your snippets") {
                if store.snippets.isEmpty {
                    Text("No snippets yet — add one below.").foregroundStyle(.secondary)
                }
                ForEach(store.snippets) { snippet in
                    SnippetCard(store: store, id: snippet.id)
                }
                Button {
                    store.add(Snippet(phrases: [""], text: ""))
                } label: {
                    Label("Add Snippet", systemImage: "plus")
                }
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 360, idealHeight: 720, maxHeight: .infinity)
        // Snippets left with neither a phrase nor text don't stay behind.
        .onDisappear {
            for snippet in store.snippets { store.removeIfEmpty(id: snippet.id) }
        }
    }
}

/// One snippet, edited in place; every change is saved straight away.
private struct SnippetCard: View {
    let store: SnippetStore
    let id: UUID

    private var snippet: Snippet? { store.snippets.first { $0.id == id } }

    var body: some View {
        if let snippet {
            VStack(alignment: .leading, spacing: 8) {
                Text("When I say").font(.caption.bold()).foregroundStyle(.secondary)
                // Always at least one field, even for a snippet without phrases yet.
                ForEach(0..<max(1, snippet.phrases.count), id: \.self) { index in
                    HStack {
                        // A hidden label and a real placeholder: in a grouped Form the title would
                        // otherwise become a row label, with a borderless field that's easy to miss.
                        TextField("When I say", text: phraseBinding(index), prompt: Text("e.g. insert my signature"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                        if snippet.phrases.count > 1 {
                            Button {
                                change { $0.phrases.remove(at: index) }
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).help("Remove this phrase")
                        }
                    }
                }
                Button("Add another phrase") { change { $0.phrases.append("") } }
                    .buttonStyle(.link).font(.caption)

                Text("Insert").font(.caption.bold()).foregroundStyle(.secondary)
                TextEditor(text: textBinding)
                    .font(.body)
                    .frame(minHeight: 70)
                    .overlay(alignment: .topLeading) {
                        if snippet.text.isEmpty {
                            Text("e.g. Best regards,\nJohan Zetterström")
                                .foregroundStyle(.tertiary).padding(.leading, 5).padding(.top, 1)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))

                ForEach(Array(snippet.problems.enumerated()), id: \.offset) { _, problem in
                    Label(Self.message(problem), systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Spacer()
                    Button("Delete Snippet", role: .destructive) { store.remove(id: id) }
                        .font(.caption)
                }
            }
            .padding(.vertical, 4)
        }
    }

    static func message(_ problem: Snippet.Problem) -> String {
        switch problem {
        case .noPhrase: "Add a phrase to say — without one, this snippet can't be used."
        case .noText: "Add the text to insert."
        case .oneWordPhrase(let word):
            "“\(word)” is a single word, so it would also fire in ordinary sentences. Try “insert my \(word)”."
        }
    }

    private func change(_ edit: (inout Snippet) -> Void) {
        guard var edited = snippet else { return }
        edit(&edited)
        store.update(edited)
    }

    private func phraseBinding(_ index: Int) -> Binding<String> {
        Binding(get: { snippet.flatMap { $0.phrases.indices.contains(index) ? $0.phrases[index] : nil } ?? "" },
                set: { value in
                    change {
                        if $0.phrases.indices.contains(index) {
                            $0.phrases[index] = value
                        } else {
                            $0.phrases.append(value)   // the empty field shown for a snippet without phrases
                        }
                    }
                })
    }

    private var textBinding: Binding<String> {
        Binding(get: { snippet?.text ?? "" }, set: { value in change { $0.text = value } })
    }
}
