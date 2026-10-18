import Foundation

// The domain model shared by every module. Values only: the store (ClipStore) owns persistence, ClipboardKit fills
// items from the pasteboard, StripKit draws them, SyncKit ships them between Macs, MCPKit serves them to clients.

// MARK: - Item kind

/// What an item is, decided once when it is captured or edited (behaviour.md §2.5). `richText` and `html` are text
/// whose richest representation is RTF/RTFD or HTML; they show, filter and search as text.
public enum ItemKind: String, Codable, CaseIterable, Hashable, Sendable {
    case text, richText, html, link, color, image, files, unknown

    /// The `type:` search filter (and MCP `type`) value this kind answers to.
    public var typeFilter: ItemTypeFilter {
        switch self {
        case .text, .richText, .html: .text
        case .link: .link
        case .color: .color
        case .image: .image
        case .files: .file
        case .unknown: .unknown
        }
    }

    public var isText: Bool { typeFilter == .text }
}

/// The item types a user can filter by: `type:text`, `type:link`, … (behaviour.md §4.7, §14.2).
public enum ItemTypeFilter: String, Codable, CaseIterable, Hashable, Sendable {
    case text, link, image, file, color, unknown

    /// Accepts the singular, the plural and a few synonyms, case-insensitively: "links", "files", "colour", "url".
    public init?(filterValue: String) {
        let v = filterValue.trimmingCharacters(in: .whitespaces).lowercased()
        switch v {
        case "text", "texts", "rich", "richtext", "html": self = .text
        case "link", "links", "url", "urls": self = .link
        case "image", "images", "picture", "pictures", "photo", "photos": self = .image
        case "file", "files": self = .file
        case "color", "colors", "colour", "colours": self = .color
        case "unknown", "other": self = .unknown
        default: return nil
        }
    }

    /// Every kind this filter matches.
    public var kinds: Set<ItemKind> { Set(ItemKind.allCases.filter { $0.typeFilter == self }) }
}

// MARK: - Payload

/// A stored piece of binary data, addressed by its content: `digest` is the lowercase hex SHA-256 of the bytes. The
/// store decides where the bytes live (inline in SQLite or as a file under `SuperPastePaths.blobs`); read them with
/// `ItemStoring.data(for:)`. Equal bytes always give equal refs, so blobs dedupe and sync by digest.
public struct BlobRef: Codable, Hashable, Sendable {
    public var digest: String
    public var size: Int

    public init(digest: String, size: Int) {
        self.digest = digest; self.size = size
    }

    /// The ref for `data` (hashes it).
    public init(of data: Data) {
        self.init(digest: ClipChecksum.hex(of: data), size: data.count)
    }
}

/// One stored pasteboard representation: a pasteboard type (UTI string such as `public.utf8-plain-text`, or a legacy
/// type name) and its bytes.
public struct PasteboardRep: Codable, Hashable, Sendable {
    public var type: String
    public var blob: BlobRef

    public init(type: String, blob: BlobRef) {
        self.type = type; self.blob = blob
    }
}

/// One stored `NSPasteboardItem`: every type it carried, in the order the pasteboard listed them (richest first).
/// An item's payload is an array of these: a copy of three files is three entries.
public struct PasteboardEntry: Codable, Hashable, Sendable {
    public var reps: [PasteboardRep]

    public init(reps: [PasteboardRep]) { self.reps = reps }

    public func rep(_ type: String) -> PasteboardRep? { reps.first { $0.type == type } }
}

/// A representation with its bytes, as read from (or about to be written to) a pasteboard.
public struct RepData: Hashable, Sendable {
    public var type: String
    public var data: Data

    public init(type: String, data: Data) {
        self.type = type; self.data = data
    }
}

/// A pasteboard item with its bytes; see `PasteboardEntry`.
public struct EntryData: Hashable, Sendable {
    public var reps: [RepData]

    public init(reps: [RepData]) { self.reps = reps }

    public func data(_ type: String) -> Data? { reps.first { $0.type == type }?.data }
}

// MARK: - Sources

/// The app an item was copied from (behaviour.md §2.7).
public struct AppRecord: Codable, Hashable, Sendable {
    public var bundleID: String
    public var name: String
    /// The card header colour as "#RRGGBB": from the known-app table, else derived from the icon. Nil: gray.
    public var colorHex: String?
    /// The app's icon as PNG, kept so items synced from another Mac still show it.
    public var icon: BlobRef?

    public init(bundleID: String, name: String, colorHex: String? = nil, icon: BlobRef? = nil) {
        self.bundleID = bundleID; self.name = name; self.colorHex = colorHex; self.icon = icon
    }
}

public enum DeviceFamily: String, Codable, CaseIterable, Hashable, Sendable {
    case mac, iPhone, iPad
}

/// The device an item was copied on.
public struct Device: Codable, Hashable, Sendable, Identifiable {
    /// Stable per Mac: a SHA-256 of the hardware UUID (never the raw serial or UUID). See `Device.current`.
    public var id: String
    public var name: String
    public var family: DeviceFamily
    /// The Super Paste version that last wrote from this device.
    public var appVersion: String?

    public init(id: String, name: String, family: DeviceFamily = .mac, appVersion: String? = nil) {
        self.id = id; self.name = name; self.family = family; self.appVersion = appVersion
    }
}

/// Link preview data (behaviour.md §2.8). `title` starts as the pasteboard's `public.url-name` when present; the rest
/// arrives later from LinkPresentation when Generate Link Previews is on.
public struct LinkMetadata: Codable, Hashable, Sendable {
    public var url: String
    public var title: String?
    /// Favicon (PNG).
    public var icon: BlobRef?
    /// Preview image, e.g. og:image (PNG or JPEG).
    public var image: BlobRef?
    /// When LinkPresentation answered; nil until then (or when previews are off).
    public var fetchedAt: Date?

    public init(url: String, title: String? = nil, icon: BlobRef? = nil, image: BlobRef? = nil, fetchedAt: Date? = nil) {
        self.url = url; self.title = title; self.icon = icon; self.image = image; self.fetchedAt = fetchedAt
    }
}

public struct PixelSize: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width; self.height = height
    }
}

// MARK: - Item

/// An item's place in a pinboard. `order` sorts ascending; the store hands out fractional values so a move rewrites
/// only the moved item (which keeps sync conflicts small).
public struct PinboardPin: Codable, Hashable, Sendable {
    public var pinboardID: UUID
    public var order: Double

    public init(pinboardID: UUID, order: Double) {
        self.pinboardID = pinboardID; self.order = order
    }
}

/// One clipboard item: everything that was on the pasteboard for one copy, plus what the strip needs to draw it
/// without touching the payload bytes.
public struct ClipItem: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var createdAt: Date
    /// Last change to anything synced (content, title, pins, link metadata). Sync is last-writer-wins on this.
    public var updatedAt: Date
    /// When the item entered the clipboard history, or was copied again and moved to the front. History sorts on it,
    /// newest first; retention prunes on it. Nil for an item created straight into a pinboard ("pinned-only"),
    /// which never shows in history.
    public var copiedAt: Date?
    /// When it was last pasted or copied out of Super Paste.
    public var lastUsedAt: Date?

    public var kind: ItemKind
    /// The user's name for the item (Rename, ⌘R). Nil shows the default header (the source app or type).
    public var title: String?
    /// Plain text for display: at most `ClipItem.previewTextLimit` characters. Full text for search lives in the
    /// store; the full payload in `payload`.
    public var text: String
    /// Length of the full plain text in characters ("N characters" footer); 0 when there is none.
    public var textLength: Int

    public var sourceApp: AppRecord?
    public var device: Device?
    /// Total payload size in bytes.
    public var byteSize: Int
    /// SHA-256 of the payload (`ClipChecksum.of(_:)`); equal content gives an equal checksum, which dedupes captures.
    public var checksum: String

    /// Pinboards this item is pinned to. Pinned items are never pruned and survive Erase History.
    public var pins: [PinboardPin]
    /// Everything that was on the pasteboard, ready to write back.
    public var payload: [PasteboardEntry]

    /// Images: pixel size of the original.
    public var imageSize: PixelSize?
    /// Downscaled preview (PNG): image thumbnail, or the Quick Look thumbnail of a file.
    public var thumbnail: BlobRef?
    /// Files: POSIX paths, in pasteboard order.
    public var filePaths: [String]
    /// Links: URL, title and preview images.
    public var link: LinkMetadata?

    /// The longest `text` the store keeps on an item (cards show the first 20 000 characters; ui-reference §4.5).
    public static let previewTextLimit = 20_000

    public init(id: UUID = UUID(), createdAt: Date = Date(), updatedAt: Date? = nil, copiedAt: Date? = nil,
                lastUsedAt: Date? = nil, kind: ItemKind, title: String? = nil, text: String = "", textLength: Int? = nil,
                sourceApp: AppRecord? = nil, device: Device? = nil, byteSize: Int = 0, checksum: String = "",
                pins: [PinboardPin] = [], payload: [PasteboardEntry] = [], imageSize: PixelSize? = nil,
                thumbnail: BlobRef? = nil, filePaths: [String] = [], link: LinkMetadata? = nil) {
        self.id = id; self.createdAt = createdAt; self.updatedAt = updatedAt ?? createdAt; self.copiedAt = copiedAt
        self.lastUsedAt = lastUsedAt; self.kind = kind; self.title = title
        self.text = String(text.prefix(Self.previewTextLimit)); self.textLength = textLength ?? text.count
        self.sourceApp = sourceApp; self.device = device; self.byteSize = byteSize; self.checksum = checksum
        self.pins = pins; self.payload = payload; self.imageSize = imageSize; self.thumbnail = thumbnail
        self.filePaths = filePaths; self.link = link
    }

    public var pinboardIDs: [UUID] { pins.map(\.pinboardID) }
    public var isPinned: Bool { !pins.isEmpty }
    /// Whether it shows in the clipboard history.
    public var isInHistory: Bool { copiedAt != nil }
    public func isPinned(to pinboardID: UUID) -> Bool { pins.contains { $0.pinboardID == pinboardID } }

    /// Every blob this item references (payload, thumbnail, link images, app icon): what sync must carry and what
    /// keeps a blob alive.
    public var blobRefs: [BlobRef] {
        var refs = payload.flatMap { $0.reps.map(\.blob) }
        refs += [thumbnail, link?.icon, link?.image, sourceApp?.icon].compactMap { $0 }
        return refs
    }
}

// MARK: - Pinboards

/// The eight pinboard colours (behaviour.md §5). Resolved to screen colours by `SPColor.pinboard(_:style:)`.
public enum PinboardColor: String, Codable, CaseIterable, Hashable, Sendable {
    case red, orange, yellow, green, blue, purple, pink, gray
}

public struct Pinboard: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var color: PinboardColor
    /// Tab position, ascending.
    public var order: Int
    /// Optional shortcut that opens the strip on this pinboard.
    public var shortcut: Shortcut?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, color: PinboardColor, order: Int, shortcut: Shortcut? = nil,
                createdAt: Date = Date(), updatedAt: Date? = nil) {
        self.id = id; self.name = name; self.color = color; self.order = order; self.shortcut = shortcut
        self.createdAt = createdAt; self.updatedAt = updatedAt ?? createdAt
    }
}

/// A list the strip can show: the clipboard history or one pinboard. `id` is what `selectedListIdentifier` and the
/// `superpaste://list/<id>` route carry.
public enum ListScope: Hashable, Codable, Sendable {
    /// Items with `copiedAt`, newest first (pinned ones included).
    case history
    /// Items pinned to the pinboard, in pin order.
    case pinboard(UUID)
    /// Every item, history and pinned-only, newest first (`copiedAt`, else `createdAt`). Used by MCP search.
    case all

    public var id: String {
        switch self {
        case .history: "history"
        case .pinboard(let id): id.uuidString
        case .all: "all"
        }
    }

    public init?(id: String) {
        switch id.lowercased() {
        case "history", "clipboard": self = .history
        case "all": self = .all
        default:
            guard let uuid = UUID(uuidString: id) else { return nil }
            self = .pinboard(uuid)
        }
    }
}
