import AppKit
import Core
import History
import HUD
import Preferences
import SwiftUI

struct HistoryView: View {
    let store: HistoryStore?
    let settings: SettingsStore
    private var highlight: Highlight { settings.highlight }
    @State private var query = ""
    @State private var confirmClear = false

    var body: some View {
        Group {
            if let store {
                list(store)
            } else {
                ContentUnavailableView("History unavailable", systemImage: "exclamationmark.triangle",
                                       description: Text("The history database could not be opened."))
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    private func list(_ store: HistoryStore) -> some View {
        let _ = store.revision   // re-query when the store changes
        let items = store.items(matching: query)
        let stats = store.stats()
        return VStack(spacing: 0) {
            if stats.words > 0 {
                StatsHeader(stats: stats, highlight: highlight).padding([.horizontal, .top], 12)
            }
            List(items) { item in
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.record.date, style: .time).font(.caption).foregroundStyle(.secondary)
                        Text(item.record.date, style: .date).font(.caption).foregroundStyle(.secondary)
                        if let language = item.record.language { Text(language.flag).font(.caption) }
                        if let app = appName(item.record.appBundleID) {
                            Text(app).font(.caption).foregroundStyle(.secondary)
                        }
                        if !item.record.pasted {
                            Label("not pasted", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    Text(item.record.finalText).lineLimit(2).textSelection(.enabled)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.record.finalText, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless).help("Copy")
                Button(role: .destructive) { store.delete(item.id) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("Delete")
            }
            .padding(.vertical, 2)
        }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(query.isEmpty ? "No dictations yet" : "No matches",
                                       systemImage: "clock.arrow.circlepath")
            }
        }
        .searchable(text: $query, prompt: "Search history")
        .toolbar {
            Button("Clear All", role: .destructive) { confirmClear = true }
                .disabled(items.isEmpty && query.isEmpty)
        }
        .confirmationDialog("Delete all dictation history?", isPresented: $confirmClear) {
            Button("Delete All", role: .destructive) { store.deleteAll() }
        }
    }

    private func appName(_ bundleID: String?) -> String? {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path)
    }
}

private struct StatsHeader: View {
    let stats: DictationStats
    let highlight: Highlight

    var body: some View {
        HStack(spacing: 10) {
            tile(stats.words.formatted(), "words this week")
            tile(StatsFormatter.savedText(stats.timeSaved), "time saved")
            VStack(alignment: .leading, spacing: 6) {
                if let split = StatsFormatter.languagePercents(stats) {
                    Text("🇸🇪 \(split.swedish)%  ·  🇬🇧 \(split.english)%")
                        .font(.headline)
                    GeometryReader { proxy in
                        HStack(spacing: 0) {
                            AuroraTheme.start(highlight).frame(width: proxy.size.width * Double(split.swedish) / 100)
                            AuroraTheme.end(highlight).frame(width: proxy.size.width * Double(split.english) / 100)
                        }
                    }
                    .frame(height: 6)
                    .clipShape(Capsule())
                } else {
                    Text("🇸🇪 · 🇬🇧").font(.headline)
                    Text("no language yet").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.bold()).foregroundStyle(AuroraTheme.gradient(highlight))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
