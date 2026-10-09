import AppKit
import Charts
import Core
import History
import HUD
import Preferences
import SwiftData
import SwiftUI

struct HistoryView: View {
    let store: HistoryStore?
    let settings: SettingsStore
    @State private var tab = Tab.dictations

    enum Tab: String, CaseIterable {
        case dictations = "Dictations"
        case stats = "Stats"
    }

    var body: some View {
        Group {
            if let store {
                content(store)
            } else {
                ContentUnavailableView("History unavailable", systemImage: "exclamationmark.triangle",
                                       description: Text("The history database could not be opened."))
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    private func content(_ store: HistoryStore) -> some View {
        let _ = store.revision   // re-query when the store changes
        let items = store.items(matching: "")
        return VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .padding(.vertical, 8)
            switch tab {
            case .dictations:
                DictationsList(store: store, items: items, highlight: settings.highlight)
            case .stats:
                StatsPane(records: items.map(\.record), retention: settings.historyRetention,
                          highlight: settings.highlight)
            }
        }
    }
}

// MARK: Dictations

private struct DictationsList: View {
    let store: HistoryStore
    let items: [HistoryItem]
    let highlight: Highlight
    @State private var filter = HistoryFilter()
    @State private var expanded: PersistentIdentifier?
    @State private var confirmClear = false

    var body: some View {
        let records = items.map(\.record)
        let now = Date()
        let shown = items.filter { filter.matches($0.record, now: now) }
        List(shown) { item in
            DictationRow(item: item, expanded: expanded == item.id, highlight: highlight, store: store)
                .contentShape(Rectangle())
                .onTapGesture { expanded = expanded == item.id ? nil : item.id }
        }
        .overlay {
            if shown.isEmpty {
                ContentUnavailableView(items.isEmpty ? "No dictations yet" : "No matches",
                                       systemImage: "clock.arrow.circlepath")
            }
        }
        .searchable(text: $filter.query, prompt: "Search history")
        .toolbar {
            ToolbarItemGroup {
                Picker("App", selection: $filter.app) {
                    Text("All apps").tag(String?.none)
                    ForEach(HistoryFilter.apps(in: records), id: \.self) { app in
                        Text(AppInfo.name(app)).tag(String?.some(app))
                    }
                }
                Picker("Language", selection: $filter.language) {
                    Text("All languages").tag(Language?.none)
                    ForEach(HistoryFilter.languages(in: records), id: \.self) { language in
                        Text("\(language.flag) \(language.displayName)").tag(Language?.some(language))
                    }
                }
                Picker("Period", selection: $filter.period) {
                    ForEach(HistoryPeriod.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("Pasted", selection: $filter.notPastedOnly) {
                    Text("All").tag(false)
                    Text("Not pasted only").tag(true)
                }
                if !filter.isDefault {
                    Button("Clear filters") { filter = filter.cleared() }
                }
                Button("Clear All", role: .destructive) { confirmClear = true }
                    .disabled(items.isEmpty)
            }
        }
        .confirmationDialog("Delete all dictation history?", isPresented: $confirmClear) {
            Button("Delete All", role: .destructive) { store.deleteAll() }
        }
    }
}

private struct DictationRow: View {
    let item: HistoryItem
    let expanded: Bool
    let highlight: Highlight
    let store: HistoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.record.date, style: .time).font(.caption).foregroundStyle(.secondary)
                        Text(item.record.date, style: .date).font(.caption).foregroundStyle(.secondary)
                        if let language = item.record.language { Text(language.flag).font(.caption) }
                        if let app = item.record.appBundleID {
                            Text(AppInfo.name(app)).font(.caption).foregroundStyle(.secondary)
                        }
                        if !item.record.pasted {
                            Label("not pasted", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    Text(item.record.finalText).lineLimit(expanded ? nil : 2).textSelection(.enabled)
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
            if expanded { CleanupDiff(record: item.record, highlight: highlight) }
        }
        .padding(.vertical, 2)
    }
}

/// What was heard next to what was pasted, with cleanup's changes marked.
private struct CleanupDiff: View {
    let record: DictationRecord
    let highlight: Highlight

    var body: some View {
        let diff = WordDiff.diff(raw: record.rawText, final: record.finalText)
        VStack(alignment: .leading, spacing: 6) {
            if record.rawText == record.finalText {
                Text("No changes by cleanup").font(.caption).foregroundStyle(.secondary)
            } else {
                block("Heard", diff.heard.reduce(Text("")) { text, token in
                    text + (token.changed ? Text(token.text).foregroundColor(.red).strikethrough()
                                          : Text(token.text)) + Text(" ")
                })
                block("Pasted", diff.pasted.reduce(Text("")) { text, token in
                    text + (token.changed ? Text(token.text).foregroundColor(AuroraTheme.start(highlight)).bold()
                                          : Text(token.text)) + Text(" ")
                })
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private func block(_ title: String, _ text: Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            text.textSelection(.enabled)
        }
    }
}

// MARK: Stats

private struct StatsPane: View {
    let records: [DictationRecord]
    let retention: HistoryRetention
    let highlight: Highlight
    @State private var period = HistoryPeriod.week

    var body: some View {
        let report = HistoryReport.compute(records, period: period, now: Date())
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Period", selection: $period) {
                    ForEach([HistoryPeriod.week, .month, .all], id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                if let note = retentionNote {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                if report.dictations == 0 {
                    ContentUnavailableView("No dictations in this period", systemImage: "chart.bar")
                } else {
                    HStack(spacing: 10) {
                        tile(report.words.formatted(), "words")
                        tile(StatsFormatter.savedText(report.timeSaved), "time saved")
                        tile(report.dictations.formatted(), "dictations")
                        tile(report.averageWords.formatted(), "words per dictation")
                    }
                    section(report.bucketIsWeek ? "Words per week" : "Words per day") {
                        Chart(report.buckets, id: \.start) { bucket in
                            BarMark(x: .value("Date", bucket.start, unit: report.bucketIsWeek ? .weekOfYear : .day),
                                    y: .value("Words", bucket.words))
                            .foregroundStyle(AuroraTheme.gradient(highlight))
                        }
                        .frame(height: 160)
                    }
                    section("Top apps") { TopApps(apps: report.topApps, highlight: highlight) }
                    let split = StatsFormatter.languagePercents(DictationStats(words: report.words,
                                                                               timeSaved: report.timeSaved,
                                                                               shares: report.shares))
                    if !split.isEmpty {
                        section("Languages") {
                            Text(split.map { "\($0.language.flag) \($0.percent)%" }.joined(separator: "  ·  "))
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    /// Shown when History keeps fewer days than the chosen period.
    private var retentionNote: String? {
        let kept: Int? = switch retention {
        case .day: 1
        case .week: 7
        case .month: 30
        case .off, .forever: nil
        }
        guard let kept, kept < (period.days ?? .max) else { return nil }
        return "History keeps \(kept) \(kept == 1 ? "day" : "days") — change this in Settings → History"
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

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }
}

private struct TopApps: View {
    let apps: [HistoryReport.AppWords]
    let highlight: Highlight

    var body: some View {
        let most = apps.map(\.words).max() ?? 1
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(apps.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 8) {
                    if let app = entry.app, let icon = AppInfo.icon(app) {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    } else {
                        Image(systemName: entry.isOther ? "ellipsis.circle" : "questionmark.app")
                            .frame(width: 16, height: 16)
                    }
                    Text(entry.isOther ? "Other" : entry.app.map(AppInfo.name) ?? "Unknown app")
                        .frame(width: 140, alignment: .leading).lineLimit(1)
                    GeometryReader { proxy in
                        Capsule().fill(AuroraTheme.gradient(highlight))
                            .frame(width: max(4, proxy.size.width * Double(entry.words) / Double(most)))
                    }
                    .frame(height: 8)
                    Text(entry.words.formatted()).font(.caption).foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                }
            }
        }
    }
}

/// An app's display name and icon from its bundle ID (the bundle ID when it's not installed).
private enum AppInfo {
    static func name(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func icon(_ bundleID: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}
