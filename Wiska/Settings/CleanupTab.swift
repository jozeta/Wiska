import AppKit
import Core
import Preferences
import SwiftUI

struct CleanupTab: View {
    let model: AppModel
    @State private var comparing = false

    /// Downloaded models only — plus the current choice while Gemma is being updated.
    private func languageModels(including current: LanguageModelChoice) -> [LanguageModelChoice] {
        let offered = LanguageModelChoice.offered(gemmaInstalled: model.gemmaStore.isInstalled)
        return offered.contains(current) ? offered : offered + [current]
    }


    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section("Language model") {
                Picker("Model", selection: Binding(get: { settings.languageModel },
                                                   set: { model.chooseLanguageModel($0) })) {
                    ForEach(languageModels(including: settings.languageModel), id: \.self) { Text($0.displayName).tag($0) }
                }
                if !model.gemmaStore.isInstalled {
                    Text("Download Gemma 4 E4B in the Models tab for better grammar and Swedish, also without Apple Intelligence.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Fix grammar", isOn: $settings.fixGrammar)
                Text("Light and Polished also fix grammar mistakes — “He go… buyed” → “He went… bought”, “en stort hus” → “ett stort hus”.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Compare models…") { comparing = true }
            }
            Section("Cleanup") {
                Picker("Level", selection: $settings.cleanupLevel) {
                    ForEach(CleanupLevel.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(settings.cleanupLevel.summary).font(.caption).foregroundStyle(.secondary)
                Text("Say “new line”, “new paragraph” or “scratch that” in your language: "
                     + settings.enabledLanguages.map { "\($0.flag) “\($0.rules.newLine[0])”" }.joined(separator: ", ") + ".")
                    .font(.caption).foregroundStyle(.secondary)
                if model.cleanupUnavailable {
                    Text("No language model is available — basic cleanup is used.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Section("Styles") {
                ForEach(AppCategory.allCases.filter { $0 != .code }, id: \.self) { category in
                    Picker(selection: Binding(get: { settings.style(for: category) },
                                              set: { settings.setStyle($0, for: category) })) {
                        ForEach(WritingStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.displayName)
                            Text(settings.style(for: category).example).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                LabeledContent("Code") {
                    Text("Exactly what you say (no rewrite)").foregroundStyle(.secondary)
                }
                Text("Lists said with a short pause between items (“first eggs, second milk”) become numbered lines; in Email, the greeting and sign-off get their own lines.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                if settings.recentApps.isEmpty {
                    Text("Apps you dictate into appear here.").foregroundStyle(.secondary)
                }
                ForEach(settings.recentApps, id: \.self) { bundleID in
                    Picker(selection: Binding(
                        get: { AppCatalog.category(for: bundleID, overrides: settings.appCategories) },
                        set: { settings.setCategory($0, for: bundleID) })) {
                        ForEach(AppCategory.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    } label: {
                        AppLabel(bundleID: bundleID)
                    }
                }
            } header: {
                HStack {
                    Text("Apps")
                    Spacer()
                    Button("Reset") { settings.resetAppCategories() }
                        .disabled(settings.appCategories.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $comparing) { CompareModelsView(model: model) }
    }
}

/// An app's icon and name, from its bundle ID.
private struct AppLabel: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 6) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 16, height: 16)
            }
            Text(url.map { FileManager.default.displayName(atPath: $0.path) }?
                    .replacingOccurrences(of: ".app", with: "") ?? bundleID)
        }
    }
}
