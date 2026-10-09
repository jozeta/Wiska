import Core
import Preferences
import SwiftUI

/// Saved instructions for command mode: "When I say <phrase> → Do this <instruction>".
struct CommandsTab: View {
    let store: CommandStore
    @State private var trial = ""

    var body: some View {
        Form {
            Section {
                Text("Hold fn+⌃ and start with a command's phrase — with text selected to change it, or with nothing selected to write something new. Say the phrase alone, or add more after a comma or “and”: “formal and a bit shorter”. More in the Help tab.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let aside = store.setAsideFile {
                Section {
                    Label("Your commands file couldn't be read, so the default commands are back. The old file was kept as \(aside.lastPathComponent) in Wiska's folder.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Section("Try it") {
                TextField("Try it", text: $trial, prompt: Text("Type what you would say, e.g. “formal and a bit shorter”"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                if !trial.trimmingCharacters(in: .whitespaces).isEmpty {
                    let instruction = CommandResolver.resolve(trial, commands: store.commands)
                    if CommandResolver.matchedCommand(trial, commands: store.commands) == nil {
                        Text("No saved command — your words are the instruction, as said.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Wiska would ask:").font(.caption).foregroundStyle(.secondary)
                            Text(instruction).textSelection(.enabled)
                        }
                    }
                }
            }

            Section("Your commands") {
                if store.commands.isEmpty {
                    Text("No commands yet — add one below.").foregroundStyle(.secondary)
                }
                ForEach(store.commands) { command in
                    CommandCard(store: store, id: command.id)
                }
                Button {
                    store.add(SavedCommand(phrases: [""], instruction: ""))
                } label: {
                    Label("Add Command", systemImage: "plus")
                }
            }
        }
        .formStyle(.grouped)
        // Commands left with neither a phrase nor an instruction don't stay behind.
        .onDisappear {
            store.removeEmpty()
        }
    }
}

/// One command, edited in place; every change is saved straight away.
private struct CommandCard: View {
    let store: CommandStore
    let id: UUID

    private var command: SavedCommand? { store.commands.first { $0.id == id } }

    var body: some View {
        if let command {
            VStack(alignment: .leading, spacing: 8) {
                Text("When I say").font(.caption.bold()).foregroundStyle(.secondary)
                // Always at least one field, even for a command without phrases yet.
                ForEach(0..<max(1, command.phrases.count), id: \.self) { index in
                    HStack {
                        // A hidden label and a real placeholder: in a grouped Form the title would
                        // otherwise become a row label, with a borderless field that's easy to miss.
                        TextField("When I say", text: phraseBinding(index), prompt: Text("e.g. formal"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                        if command.phrases.count > 1 {
                            Button {
                                change { $0.phrases.remove(at: index) }
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).help("Remove this phrase")
                        }
                    }
                }
                Button("Add another phrase") { change { $0.phrases.append("") } }
                    .buttonStyle(.link).font(.caption)

                Text("Do this").font(.caption.bold()).foregroundStyle(.secondary)
                TextField("Do this", text: instructionBinding,
                          prompt: Text("e.g. Rewrite in a formal, polite tone."), axis: .vertical)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...5)

                ForEach(Array(command.problems.enumerated()), id: \.offset) { _, problem in
                    Label(Self.message(problem), systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Spacer()
                    Button("Delete Command", role: .destructive) { store.remove(id: id) }
                        .font(.caption)
                }
            }
            .padding(.vertical, 4)
        }
    }

    static func message(_ problem: SavedCommand.Problem) -> String {
        switch problem {
        case .noPhrase: "Add a phrase to say — without one, this command can't be used."
        case .noInstruction: "Add what Wiska should do."
        }
    }

    private func change(_ edit: (inout SavedCommand) -> Void) {
        guard var edited = command else { return }
        edit(&edited)
        store.update(edited)
    }

    private func phraseBinding(_ index: Int) -> Binding<String> {
        Binding(get: { command.flatMap { $0.phrases.indices.contains(index) ? $0.phrases[index] : nil } ?? "" },
                set: { value in
                    change {
                        if $0.phrases.indices.contains(index) {
                            $0.phrases[index] = value
                        } else {
                            $0.phrases.append(value)   // the empty field shown for a command without phrases
                        }
                    }
                })
    }

    private var instructionBinding: Binding<String> {
        Binding(get: { command?.instruction ?? "" }, set: { value in change { $0.instruction = value } })
    }
}
