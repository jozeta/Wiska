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
        // The same margin below the content as beside it.
        .padding(.bottom, StatsPane.margin)
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
        let apps = HistoryFilter.apps(in: records)
        let languages = HistoryFilter.languages(in: records)
        // Re-render every minute, so "Today" rolls over at midnight while the window stays open.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let shown = items.filter { filter.matches($0.record, now: context.date) }
            List(shown) { item in
                DictationRow(item: item, expanded: expanded == item.id, highlight: highlight, store: store) {
                    expanded = expanded == item.id ? nil : item.id
                }
            }
            .overlay {
                if shown.isEmpty {
                    ContentUnavailableView(items.isEmpty ? "No dictations yet" : "No matches",
                                           systemImage: "clock.arrow.circlepath")
                }
            }
        }
        .searchable(text: $filter.query, prompt: "Search history")
        .onChange(of: records.count) {
            // A filter for an app or language that is no longer in history would leave a blank menu.
            filter = filter.validated(apps: apps, languages: languages)
        }
        .toolbar {
            ToolbarItem {
                // One menu for every filter: four separate pickers overflow a narrow window.
                Menu {
                    Picker("App", selection: $filter.app) {
                        Text("All apps").tag(String?.none)
                        ForEach(apps, id: \.self) { app in
                            Label {
                                Text(AppInfo.name(app))
                            } icon: {
                                if let icon = AppInfo.icon(app) { Image(nsImage: icon) }
                            }
                            .tag(String?.some(app))
                        }
                    }
                    Picker("Language", selection: $filter.language) {
                        Text("All languages").tag(Language?.none)
                        ForEach(languages, id: \.self) { language in
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
                    Divider()
                    Button("Clear filters") { filter = filter.cleared() }
                        .disabled(filter.isDefault)
                } label: {
                    Label(filterTitle, systemImage: filter.isDefault ? "line.3.horizontal.decrease.circle"
                                                                     : "line.3.horizontal.decrease.circle.fill")
                }
                .help("Filter")
            }
            ToolbarItem {
                // Kept apart from the filters: deleting everything is a different kind of action.
                Menu {
                    Button("Clear All…", role: .destructive) { confirmClear = true }
                        .disabled(items.isEmpty)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Delete all dictation history?", isPresented: $confirmClear) {
            Button("Delete All", role: .destructive) { store.deleteAll() }
        }
    }

    /// "Filter", or "Filter (2)" with two filters on.
    private var filterTitle: String {
        let active = [filter.app != nil, filter.language != nil, filter.period != .all, filter.notPastedOnly]
            .filter { $0 }.count
        return active == 0 ? "Filter" : "Filter (\(active))"
    }
}

private struct DictationRow: View {
    let item: HistoryItem
    let expanded: Bool
    let highlight: Highlight
    let store: HistoryStore
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    // Only the header line toggles, so the texts below stay selectable.
                    HStack(spacing: 6) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption2).foregroundStyle(.secondary)
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
                    .contentShape(Rectangle())
                    .onTapGesture(perform: toggle)
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
    /// The space around the Stats content; the window keeps the same space at its bottom.
    static let margin: CGFloat = 12

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
                    if !report.speed.isEmpty {
                        section("Speed") { SpeedChart(speed: report.speed, highlight: highlight) }
                    }
                    let split = StatsFormatter.languagePercents(DictationStats(words: report.words,
                                                                               timeSaved: report.timeSaved,
                                                                               shares: report.shares))
                    if !split.isEmpty {
                        section("Languages") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(split.map { "\($0.language.flag) \($0.percent)%" }.joined(separator: "  ·  "))
                                GeometryReader { proxy in
                                    HStack(spacing: 0) {
                                        ForEach(Array(split.enumerated()), id: \.offset) { index, entry in
                                            AuroraTheme.color(highlight, at: split.count == 1 ? 0
                                                                  : Double(index) / Double(split.count - 1))
                                                .frame(width: proxy.size.width * Double(entry.percent) / 100)
                                        }
                                    }
                                }
                                .frame(height: 6)
                                .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            .padding([.horizontal, .top], Self.margin)
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

/// From releasing fn to the text appearing, per speech engine: typical (median) times, split
/// into turning the audio into words, cleaning them up, and the rest (the release tail and pasting).
private struct SpeedChart: View {
    let speed: [HistoryReport.EngineSpeed]
    let highlight: Highlight

    private struct Step: Identifiable {
        let engine: String
        let name: String
        let seconds: Double
        var id: String { engine + name }
    }

    private var steps: [Step] {
        speed.flatMap { entry in
            let name = entry.engine.displayName
            let rest = max(0, entry.total - entry.transcription - entry.cleanup)
            return [Step(engine: name, name: "Transcription", seconds: entry.transcription),
                    Step(engine: name, name: "Cleanup", seconds: entry.cleanup),
                    Step(engine: name, name: "Paste", seconds: rest)]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Chart(steps) { step in
                BarMark(x: .value("Seconds", step.seconds), y: .value("Engine", step.engine))
                    .foregroundStyle(by: .value("Step", step.name))
            }
            .chartForegroundStyleScale(["Transcription": AuroraTheme.color(highlight, at: 0),
                                        "Cleanup": AuroraTheme.color(highlight, at: 0.5),
                                        "Paste": AuroraTheme.color(highlight, at: 1)])
            .chartXAxisLabel("seconds, release → text")
            .frame(height: CGFloat(speed.count) * 34 + 50)
            ForEach(speed, id: \.engine) { entry in
                Text("\(entry.engine.displayName): typically \(Self.format(entry.total)) from release to text, over \(entry.dictations) \(entry.dictations == 1 ? "dictation" : "dictations")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        seconds < 1 ? "\(Int((seconds * 1000).rounded())) ms" : String(format: "%.1f s", seconds)
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

    /// The app icon at menu size (16 pt): NSWorkspace hands out 32 pt images, too tall for a menu row.
    static func icon(_ bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let icon = NSWorkspace.shared.icon(forFile: url.path).copy() as? NSImage else { return nil }
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}
