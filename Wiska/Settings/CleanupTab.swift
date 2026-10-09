import AppKit
import Core
import Preferences
import SwiftUI

struct CleanupTab: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        Form {
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
                    Text("Apple Intelligence is unavailable — basic cleanup is used.")
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
                Text("Spoken lists (“first … second …”) become numbered lines; in Email, the greeting and sign-off get their own lines.")
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
        .fixedSize(horizontal: false, vertical: true)
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
