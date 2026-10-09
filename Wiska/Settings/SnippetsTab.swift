import Core
import Preferences
import SwiftUI

/// Saved texts inserted by voice ("insert my signature").
struct SnippetsTab: View {
    let store: SnippetStore
    @State private var selection: UUID?

    var body: some View {
        Form {
            Section {
                if store.snippets.isEmpty {
                    Text("No snippets yet.").foregroundStyle(.secondary)
                }
                ForEach(store.snippets) { snippet in
                    Button {
                        selection = selection == snippet.id ? nil : snippet.id
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snippet.name.isEmpty ? "Untitled" : snippet.name)
                            Text(snippet.text.components(separatedBy: "\n").first ?? "")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if selection == snippet.id {
                        SnippetEditor(snippet: snippet, store: store) { selection = nil }
                    }
                }
                Button("Add Snippet") {
                    let snippet = Snippet(name: "", text: "")
                    store.add(snippet)
                    selection = snippet.id
                }
            } header: {
                Text("Snippets")
            } footer: {
                Text("Say “insert my <name>” — in Swedish “infoga min <name>” — anywhere in a dictation. The text is inserted exactly as written.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 440)
    }
}

private struct SnippetEditor: View {
    let snippet: Snippet
    let store: SnippetStore
    let close: () -> Void
    @State private var name = ""
    @State private var aliases = ""
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name (what you say)", text: $name)
            TextField("Other names, comma-separated", text: $aliases)
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 80)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
            HStack {
                Button("Delete", role: .destructive) {
                    store.remove(id: snippet.id)
                    close()
                }
                Spacer()
                Button("Done") { close() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            name = snippet.name
            aliases = snippet.aliases.joined(separator: ", ")
            text = snippet.text
        }
        // Saved as you type: closing the editor any way (another row, another tab) keeps the edits.
        .onChange(of: name) { save() }
        .onChange(of: aliases) { save() }
        .onChange(of: text) { save() }
        // An abandoned "Add Snippet" doesn't leave an empty row behind.
        .onDisappear { store.removeIfEmpty(id: snippet.id) }
    }

    private func save() {
        var edited = snippet
        edited.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        edited.aliases = aliases.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        edited.text = text
        guard edited != snippet else { return }
        store.update(edited)
    }
}
