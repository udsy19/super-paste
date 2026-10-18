import AppKit
import SuperPasteCore

// The pure capture rules (behaviour.md §2.2–§2.4): which copies are skipped, which types are dropped per app, and how
// a payload is cleaned before it is stored.

/// Matching bundle ids against the Ignore Applications list (`CaptureDefaults.ignoredApps` documents the forms).
package enum IgnoredApps {
    /// An entry matches exactly or as a dotted prefix ("com.1password" matches "com.1password.1password"); an entry
    /// that starts with "." matches as a suffix (".nordpass" matches "com.nordsec.nordpass"). Case-insensitive, as
    /// bundle ids are.
    package static func matches(_ bundleID: String, entry: String) -> Bool {
        let id = bundleID.lowercased(), pattern = entry.trimmingCharacters(in: .whitespaces).lowercased()
        guard !id.isEmpty, !pattern.isEmpty, pattern != "." else { return false }
        if pattern.hasPrefix(".") { return id.hasSuffix(pattern) }
        return id == pattern || id.hasPrefix(pattern + ".")
    }

    /// The first list entry that matches `bundleID`.
    package static func match(_ bundleID: String, in list: [String]) -> String? {
        list.first { matches(bundleID, entry: $0) }
    }
}

/// Per-app pasteboard quirks (behaviour.md §2.4).
package struct QuirkRule: Sendable {
    /// The app the rule is for; nil for every app.
    package var bundleID: String?
    /// Types that are neither stored nor written back.
    package var droppedTypes: Set<String>
    /// Text types that decide the item: when one is present the copy is text even though the app also put an
    /// image on the pasteboard, and its text is read from these types first, in this order.
    package var textTypes: [String]

    package init(bundleID: String?, droppedTypes: Set<String> = [], textTypes: [String] = []) {
        self.bundleID = bundleID; self.droppedTypes = droppedTypes; self.textTypes = textTypes
    }

    package static let all: [QuirkRule] = [
        QuirkRule(bundleID: nil, droppedTypes: PasteboardType.banned),
        // Copies a temporary file and a PNG next to what was actually copied.
        QuirkRule(bundleID: "org.mozilla.firefoxdeveloperedition",
                  droppedTypes: [NSPasteboard.PasteboardType.fileURL.rawValue, NSPasteboard.PasteboardType.png.rawValue]),
        // Cell copies carry a picture of the cells; the text is what was meant. Its UTF-16 text is the reliable one.
        QuirkRule(bundleID: "com.microsoft.Excel", textTypes: [TextTypes.utf16, PasteboardType.plainText]),
    ]

    /// The rules that apply to a copy from `bundleID` (the all-apps rule always does).
    package static func rules(for bundleID: String?) -> [QuirkRule] {
        all.filter { rule in
            guard let id = rule.bundleID else { return true }
            return bundleID?.caseInsensitiveCompare(id) == .orderedSame
        }
    }

    package static func droppedTypes(for bundleID: String?) -> Set<String> {
        rules(for: bundleID).reduce(into: Set<String>()) { $0.formUnion($1.droppedTypes) }
    }

    package static func textTypes(for bundleID: String?) -> [String] {
        rules(for: bundleID).flatMap(\.textTypes)
    }
}

/// Where a copy came from (behaviour.md §2.3.1, §2.7).
package struct CaptureSource: Equatable, Sendable {
    package var bundleID: String
    /// The app's name when known (the running app's), else looked up from the bundle id.
    package var name: String?

    package init(bundleID: String, name: String?) {
        self.bundleID = bundleID; self.name = name
    }

    /// The `org.nspasteboard.source` bundle id when the pasteboard carries one, else the frontmost app; nil when
    /// neither is known.
    package static func resolve(marker: String?, frontmost: PasteTarget?) -> CaptureSource? {
        if let marker = marker?.trimmingCharacters(in: .whitespacesAndNewlines), !marker.isEmpty {
            let name = frontmost?.bundleID?.caseInsensitiveCompare(marker) == .orderedSame ? frontmost?.name : nil
            return CaptureSource(bundleID: marker, name: name)
        }
        guard let frontmost, let id = frontmost.bundleID, !id.isEmpty else { return nil }
        return CaptureSource(bundleID: id, name: frontmost.name)
    }
}

/// Whether a pasteboard change is captured (behaviour.md §2.3), decided from its types and source alone, before any
/// content is read.
package enum CaptureDecision: Equatable, Sendable {
    case capture(CaptureSource)
    /// Super Paste wrote it (paste, copy, Paste Stack): `itemID` is the marked item, if any.
    case ownWrite(itemID: UUID?)
    case noItems
    case noSource
    case ignoredApp(String)
    case ignoredType(String)
}

package enum CaptureFilter {
    /// - Parameters:
    ///   - types: each pasteboard item's types, in pasteboard order.
    ///   - itemIDMarker: the `PasteboardType.itemID` string, when present.
    ///   - sourceMarker: the `org.nspasteboard.source` bundle id, when present.
    package static func evaluate(types: [[String]], itemIDMarker: String?, sourceMarker: String?, frontmost: PasteTarget?,
                                 ownBundleID: String, ignoredApps: [String], ignoredTypes: [String]) -> CaptureDecision {
        guard types.contains(where: { !$0.isEmpty }) else { return .noItems }
        let all = types.flatMap { $0 }
        if all.contains(PasteboardType.itemID) {
            return .ownWrite(itemID: itemIDMarker.flatMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespaces)) })
        }
        if let marker = sourceMarker, marker.caseInsensitiveCompare(ownBundleID) == .orderedSame {
            return .ownWrite(itemID: nil)
        }
        let ignored = Set(ignoredTypes)
        if let type = all.first(where: ignored.contains) { return .ignoredType(type) }
        guard let source = CaptureSource.resolve(marker: sourceMarker, frontmost: frontmost) else { return .noSource }
        // A password manager is skipped whether it is frontmost or named by the source marker.
        for id in [source.bundleID, frontmost?.bundleID].compactMap({ $0 }) where IgnoredApps.match(id, in: ignoredApps) != nil {
            return .ignoredApp(id)
        }
        return .capture(source)
    }
}

/// Cleaning a payload read from the pasteboard (behaviour.md §2.2, §2.4).
package enum CapturePayload {
    /// The largest representation stored; bigger ones are skipped (behaviour.md §22.3 gap 1).
    package static let maxTypeSize = 50 * 1024 * 1024

    /// Drops `dropped` types and the volatile markers (Super Paste stamps its own on every write), then any item
    /// left without content. Empty result: nothing to capture.
    package static func clean(_ entries: [EntryData], dropping dropped: Set<String>) -> [EntryData] {
        let skipped = dropped.union(PasteboardType.volatile)
        return entries.compactMap { entry in
            let reps = entry.reps.filter { !skipped.contains($0.type) && !$0.data.isEmpty }
            return reps.isEmpty ? nil : EntryData(reps: reps)
        }
    }

    /// Whether the copy arrived by Universal Clipboard from another device.
    package static func isRemote(types: [[String]]) -> Bool {
        types.contains { $0.contains(PasteboardType.remoteClipboard) }
    }
}
