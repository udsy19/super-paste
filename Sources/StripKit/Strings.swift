import Foundation
import SuperPasteCore

/// Every user-visible string in the strip, from docs/specs/strings.md ("Paste" becomes "Super Paste").
enum L10n {
    // Empty states (§4.9)
    static let historyEmpty = "History is empty"
    static let pinboardEmpty = "Pinboard is empty"
    static let nothingFound = "Nothing found"

    // Toolbar, search, filters (§3)
    static let search = "Search"
    static let filtersTooltip = "Filters (⌘F)"
    static let clipboard = "Clipboard"
    static let createPinboard = "Create Pinboard"
    static let untitled = "Untitled"
    static let more = "More"
    static let less = "Less"
    static let today = "Today"
    static let yesterday = "Yesterday"
    static let last7Days = "Last 7 days"
    static let last30Days = "Last 30 days"

    static func filterSection(_ type: SearchQuery.FilterType) -> String {
        switch type {
        case .app: "App"
        case .date: "Date"
        case .device: "Device"
        case .pinboard: "Pinboard"
        case .type: "Type"
        case .title: "Title"
        }
    }

    /// "<name> (<prev>, <next> to navigate)".
    static func tabTooltip(_ name: String, previous: String?, next: String?) -> String {
        guard let previous, let next else { return name }
        return "\(name) (\(previous), \(next) to navigate)"
    }

    // Item types (card headers, filters)
    static let text = "Text"
    static let link = "Link"
    static let image = "Image"
    static let color = "Color"
    static let unknown = "Unknown"
    static let multipleFiles = "Multiple files"
    static func fileCount(_ n: Int) -> String { n == 1 ? "File" : "\(n) files" }

    static func typeFilterLabel(_ filter: ItemTypeFilter) -> String {
        switch filter {
        case .text: text
        case .link: link
        case .image: image
        case .file: "File"
        case .color: color
        case .unknown: unknown
        }
    }

    // Counts
    static func characters(_ n: Int) -> String { plural(n, "character", "characters") }
    static func words(_ n: Int) -> String { plural(n, "word", "words") }
    static func lines(_ n: Int) -> String { plural(n, "line", "lines") }
    static func selected(_ n: Int) -> String { "\(n) Selected" }

    private static func plural(_ n: Int, _ one: String, _ other: String) -> String {
        "\(n.formatted()) \(n == 1 ? one : other)"
    }

    // Item actions (§4.8)
    static let open = "Open"
    static func openWith(_ app: String) -> String { "Open with \(app)" }
    static let revealInFinder = "Reveal in Finder"
    static func showIn(_ list: String) -> String { "Show in \(list)" }
    static let currentApp = "current app"
    static func pasteTo(_ app: String?) -> String { "Paste to \(app ?? currentApp)" }
    static let pasteAsPlainText = "Paste as Plain Text"
    static let copy = "Copy"
    static let edit = "Edit"
    static let rename = "Rename"
    static let delete = "Delete"
    static let pin = "Pin"
    static let unpin = "Unpin"
    static let preview = "Preview"
    static let share = "Share"
    static let copied = "Copied"
    static let cancel = "Cancel"
    static let save = "Save"
    static let erase = "Erase"
    static let eraseHistory = "Erase History"

    // Alerts
    static func deleteItemsTitle(_ n: Int) -> String { n == 1 ? "Delete \(n) item?" : "Delete \(n) items?" }
    static func deletePinboardTitle(_ name: String) -> String { "Delete “\(name)”?" }
    static let deletePinboardText = "The Pinboard and all its content will be deleted. This action cannot be undone."
    static let eraseHistoryTitle = "Are you sure you want to erase your Clipboard History?"
    static let eraseHistoryText = "Pinned items and Pinboards won't be deleted. This action cannot be undone."

    // Preview and editors (§4.8)
    static let editText = "Edit Text"
    static let editImage = "Edit Image"
    static let editLink = "Edit Link"
    static let editColor = "Edit Color"
    static let editItem = "Edit Item"
    static let discardChanges = "Discard changes"
    static let saveChanges = "Save changes"
    static let bold = "Bold"
    static let italic = "Italic"
    static let underline = "Underline"
    static let strikethrough = "Strikethrough"
    static let writingTools = "Writing Tools"
    static let rotateLeft = "Rotate Left"
    static let rotateRight = "Rotate Right"
    static let previewUnavailable = "Preview unavailable"
    static let previewUnavailableSubtitle = "Preview can’t be shown, but the content is saved, and you’re able to paste it"

    // New Text Item (§4.9)
    static let newTextItem = "New Text Item"
    static let create = "Create"
    static let createTextItem = "Create text item"

    // Paste Stack (§3.6)
    static let pasteStack = "Paste Stack"
    static let pasteStackEmptyText = "Copy several things, then paste them in order with ⌘V."
    static let pasteStackEmptyHint = "Copy something to start. Esc to close."

    // Notification bar (§6.3)
    static let syncing = "Syncing"

    // Sidecar notifications (behaviour §11)
    static let enableDirectPasteTitle = "Enable Direct Paste"
    static let enableDirectPasteText = "Paste items directly to any app."
    static let openAtLoginTitle = "Open at Login"
    static let openAtLoginText = "Automatically launch Super Paste when you restart your Mac."
    static let enable = "Enable"
}
