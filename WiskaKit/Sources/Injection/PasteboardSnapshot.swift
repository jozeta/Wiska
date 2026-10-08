import AppKit

/// A byte-for-byte copy of every item and type on a pasteboard, in the original type order
/// (apps paste the first type they understand, so order decides rich vs plain text).
public struct PasteboardSnapshot: Equatable {
    struct Entry: Equatable {
        let type: NSPasteboard.PasteboardType
        let data: Data
    }

    let items: [[Entry]]

    @MainActor
    public static func capture(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { Entry(type: type, data: $0) } }
        }
        return PasteboardSnapshot(items: items)
    }

    @MainActor
    public func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items.map { entries in
            let item = NSPasteboardItem()
            for entry in entries { item.setData(entry.data, forType: entry.type) }
            return item
        })
    }
}
