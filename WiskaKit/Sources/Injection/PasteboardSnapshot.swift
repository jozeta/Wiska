import AppKit

/// A byte-for-byte copy of every item and type on a pasteboard.
public struct PasteboardSnapshot: Equatable {
    let items: [[NSPasteboard.PasteboardType: Data]]

    @MainActor
    public static func capture(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
        return PasteboardSnapshot(items: items)
    }

    @MainActor
    public func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        })
    }
}
