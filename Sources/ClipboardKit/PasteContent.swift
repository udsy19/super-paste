import AppKit
import SuperPasteCore

// What a paste or copy writes (behaviour.md §3.2, §3.4, §3.5): an item's stored types minus the banned ones, plain
// text when asked, several items planned into one or more pasteboard writes, Super Paste's markers on top.

package enum PasteContent {
    /// The item's stored payload with its bytes, banned and volatile types left out; a representation whose blob is
    /// missing is skipped, an item left empty is dropped.
    package static func entries(for item: ClipItem, data: (BlobRef) -> Data?) -> [EntryData] {
        let skipped = PasteboardType.banned.union(PasteboardType.volatile)
        return item.payload.compactMap { entry in
            let reps = entry.reps.compactMap { rep -> RepData? in
                guard !skipped.contains(rep.type), let bytes = data(rep.blob) else { return nil }
                return RepData(type: rep.type, data: bytes)
            }
            return reps.isEmpty ? nil : EntryData(reps: reps)
        }
    }

    /// Only the string flavours: an item with text becomes one UTF-8 plain-text representation (converted from
    /// RTF or HTML when it has no plain text of its own); an item without text (an image) is written as it is.
    package static func plainText(_ entries: [EntryData], preferring preferred: [String] = []) -> [EntryData] {
        entries.map { entry in
            guard let text = PayloadText.plainText(of: entry, preferring: preferred) else { return entry }
            return EntryData(reps: [RepData(type: PasteboardType.plainText, data: Data(text.utf8))])
        }
    }

    /// Adds Super Paste's markers to the first item: `PasteboardType.itemID` (so the monitor sees a restore, not a
    /// copy) and `org.nspasteboard.source` with Super Paste's bundle id. Markers already there are replaced.
    package static func marked(_ entries: [EntryData], itemID: UUID?, sourceBundleID: String) -> [EntryData] {
        guard var first = entries.first else { return [] }
        first.reps.removeAll { $0.type == PasteboardType.itemID || $0.type == PasteboardType.source }
        if let itemID { first.reps.append(RepData(type: PasteboardType.itemID, data: Data(itemID.uuidString.utf8))) }
        first.reps.append(RepData(type: PasteboardType.source, data: Data(sourceBundleID.utf8)))
        return [first] + entries.dropFirst()
    }
}

/// One pasteboard write.
package struct PasteStep: Equatable, Sendable {
    package var entries: [EntryData]
    /// The items it carries, in order.
    package var itemIDs: [UUID]
}

/// Planning several items into pasteboard writes (behaviour.md §3.4, gap 2: join text with newlines, paste mixed
/// kinds one after another).
package enum PastePlan {
    private enum Group: Equatable { case text, files, single }

    /// Consecutive text items (text, rich text, HTML, links, colours) join into one write, their texts separated by
    /// newlines and, unless `plainText`, their formatting kept as RTF; consecutive file items share one write; any
    /// other item is a write of its own. Items without stored bytes are skipped.
    package static func steps(for items: [ClipItem], plainText: Bool, data: (BlobRef) -> Data?) -> [PasteStep] {
        var runs: [(group: Group, members: [(item: ClipItem, entries: [EntryData])])] = []
        for item in items {
            let entries = PasteContent.entries(for: item, data: data)
            guard !entries.isEmpty else { continue }
            let group: Group
            if item.kind == .files {
                group = .files
            } else if item.kind.isText || item.kind == .link || item.kind == .color,
                      PayloadText.plainText(of: entries, preferring: textTypes(item)) != nil {
                group = .text
            } else {
                group = .single
            }
            if group != .single, let last = runs.last, last.group == group {
                runs[runs.count - 1].members.append((item, entries))
            } else {
                runs.append((group, [(item, entries)]))
            }
        }
        return runs.map { run in
            let ids = run.members.map(\.item.id)
            if run.group == .text, run.members.count > 1 {
                return PasteStep(entries: [joinedText(run.members, plainText: plainText)], itemIDs: ids)
            }
            let entries = run.members.flatMap { member in
                plainText ? PasteContent.plainText(member.entries, preferring: textTypes(member.item)) : member.entries
            }
            return PasteStep(entries: entries, itemIDs: ids)
        }
    }

    /// Every step as a single write (copying, dragging out, or pasting without Accessibility): their items one
    /// after another on the pasteboard.
    package static func merged(_ steps: [PasteStep]) -> PasteStep {
        PasteStep(entries: steps.flatMap(\.entries), itemIDs: steps.flatMap(\.itemIDs))
    }

    private static func textTypes(_ item: ClipItem) -> [String] { QuirkRule.textTypes(for: item.sourceApp?.bundleID) }

    private static func joinedText(_ members: [(item: ClipItem, entries: [EntryData])], plainText: Bool) -> EntryData {
        let text = members.compactMap { PayloadText.plainText(of: $0.entries, preferring: textTypes($0.item)) }
            .joined(separator: "\n")
        var reps = [RepData(type: PasteboardType.plainText, data: Data(text.utf8))]
        let rich = members.contains { $0.entries.contains { $0.reps.contains { TextTypes.rich.contains($0.type) } } }
        if !plainText, rich, let rtf = joinedRTF(members) {
            reps.insert(RepData(type: TextTypes.rtf, data: rtf), at: 0)
        }
        return EntryData(reps: reps)
    }

    private static func joinedRTF(_ members: [(item: ClipItem, entries: [EntryData])]) -> Data? {
        let joined = NSMutableAttributedString()
        for (index, member) in members.enumerated() {
            if index > 0 { joined.append(NSAttributedString(string: "\n")) }
            for (entryIndex, entry) in member.entries.enumerated() {
                if entryIndex > 0 { joined.append(NSAttributedString(string: "\n")) }
                joined.append(attributed(entry, preferring: textTypes(member.item)))
            }
        }
        return joined.rtf(from: NSRange(location: 0, length: joined.length),
                          documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    private static func attributed(_ entry: EntryData, preferring preferred: [String]) -> NSAttributedString {
        if let data = entry.data(TextTypes.rtf), let text = NSAttributedString(rtf: data, documentAttributes: nil) { return text }
        for type in [TextTypes.rtfd, "com.apple.rtfd"] {
            if let data = entry.data(type), let text = NSAttributedString(rtfd: data, documentAttributes: nil) { return text }
        }
        return NSAttributedString(string: PayloadText.plainText(of: entry, preferring: preferred) ?? "")
    }
}
