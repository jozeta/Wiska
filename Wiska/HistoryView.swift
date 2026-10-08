import AppKit
import Core
import History
import SwiftUI

struct HistoryView: View {
    let store: HistoryStore?
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
        return List(items) { item in
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
