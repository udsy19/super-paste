import AppKit
import SuperPasteCore

// Reading and writing payloads on an `NSPasteboard` (behaviour.md §2.2, §3.5). The pasteboard is always passed in:
// the app uses the general pasteboard, the self-test a uniquely named one.

package enum PasteboardIO {
    /// Each item's types, in pasteboard order (richest first).
    package static func types(on pasteboard: NSPasteboard) -> [[String]] {
        (pasteboard.pasteboardItems ?? []).map { $0.types.map(\.rawValue) }
    }

    /// The first item's string for `type` (the markers Super Paste and nspasteboard.org writers put on a pasteboard).
    package static func marker(_ type: String, on pasteboard: NSPasteboard) -> String? {
        for item in pasteboard.pasteboardItems ?? [] {
            if let data = item.data(forType: .init(type)), let text = String(data: data, encoding: .utf8) { return text }
        }
        return nil
    }

    /// Every item with every type except `skipping`; a type whose data is larger than `maxTypeSize` is left out.
    package static func read(from pasteboard: NSPasteboard, skipping: Set<String>,
                             maxTypeSize: Int = CapturePayload.maxTypeSize) -> [EntryData] {
        (pasteboard.pasteboardItems ?? []).map { item in
            EntryData(reps: item.types.compactMap { type -> RepData? in
                guard !skipping.contains(type.rawValue), let data = item.data(forType: type) else { return nil }
                guard data.count <= maxTypeSize else {
                    Log.clipboard.info("Skipping pasteboard type \(type.rawValue, privacy: .public): \(data.count) bytes exceeds the storable item size")
                    return nil
                }
                return RepData(type: type.rawValue, data: data)
            })
        }
    }

    /// Replaces the pasteboard's contents with `entries`; returns the new change count.
    @discardableResult
    package static func write(_ entries: [EntryData], to pasteboard: NSPasteboard) -> Int {
        pasteboard.clearContents()
        pasteboard.writeObjects(pasteboardItems(for: entries))
        return pasteboard.changeCount
    }

    package static func pasteboardItems(for entries: [EntryData]) -> [NSPasteboardItem] {
        entries.map { entry in
            let item = NSPasteboardItem()
            for rep in entry.reps { item.setData(rep.data, forType: .init(rep.type)) }
            return item
        }
    }
}
