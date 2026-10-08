import Core
import Parakeet
import Preferences
import SwiftUI

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section("Speech engine") {
                Picker("Engine", selection: $settings.engine) {
                    ForEach(SpeechEngine.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .onChange(of: settings.engine) { model.warmUpParakeetIfSelected() }
                ParakeetCard(store: model.parakeetStore) { model.parakeetModelBecameReady() }
                if model.parakeetUnavailable {
                    Text("Parakeet is selected but not ready — Apple is used until it is.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Language") {
                Picker("Mode", selection: $settings.languageMode) {
                    ForEach(LanguageMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                switch settings.languageMode {
                case .autoDetect:
                    Text("Each dictation is transcribed in English and Svenska; the more confident result is used.")
                        .font(.caption).foregroundStyle(.secondary)
                case .toggle:
                    Picker("Current language", selection: $settings.toggleLanguage) {
                        ForEach(Language.allCases, id: \.self) { Text("\($0.flag) \($0.displayName)").tag($0) }
                    }
                    Text("Quick-tap fn+⇧ to switch.").font(.caption).foregroundStyle(.secondary)
                case .perLanguageHotkeys:
                    Picker("fn dictates in", selection: $settings.primaryLanguage) {
                        ForEach(Language.allCases, id: \.self) { Text("\($0.flag) \($0.displayName)").tag($0) }
                    }
                    Text("fn+⇧ dictates in \(settings.primaryLanguage.other.displayName).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Cleanup") {
                Picker("Level", selection: $settings.cleanupLevel) {
                    ForEach(CleanupLevel.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(settings.cleanupLevel.summary).font(.caption).foregroundStyle(.secondary)
                Text("Say “new line”, “new paragraph” or “scratch that” (“ny rad”, “nytt stycke”, “stryk det”).")
                    .font(.caption).foregroundStyle(.secondary)
                if model.cleanupUnavailable {
                    Text("Apple Intelligence is unavailable — basic cleanup is used.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            DictionarySection(store: model.dictionaryStore)
            Section("History") {
                Picker("Keep history", selection: $settings.historyRetention) {
                    ForEach(HistoryRetention.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .onChange(of: settings.historyRetention) { model.applyRetention() }
                Text("Stored only on this Mac. Off deletes all history immediately.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Push-to-talk") {
                LabeledContent("Dictate", value: "Hold fn, speak, release")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding()
    }
}

private struct ParakeetCard: View {
    let store: ParakeetModelStore
    let onReady: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Parakeet TDT 0.6B v3")
                Text("On-device, 25 languages. Downloaded from Hugging Face only when you click Download.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            switch store.status {
            case .notDownloaded:
                Button("Download") { store.download() }
            case .downloading(let fraction):
                ProgressView(value: fraction).frame(width: 90)
                Button("Cancel") { store.cancelDownload() }
            case .ready:
                Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Remove") { store.remove() }
            case .failed(let message):
                Text(message).font(.caption).foregroundStyle(.red).lineLimit(2)
                Button("Retry") { store.download() }
            }
        }
        .onChange(of: store.status) { if store.status == .ready { onReady() } }
    }
}

private struct DictionarySection: View {
    let store: DictionaryStore
    @State private var newWord = ""
    @State private var heard = ""
    @State private var written = ""

    var body: some View {
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

    private func addWord() {
        store.addWord(newWord)
        newWord = ""
    }
}
