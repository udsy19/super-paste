import Foundation
import ImageIO
import UniformTypeIdentifiers
import SuperPasteCore

/// The eleven MCP tools (behaviour.md §14.2), implemented over `ItemStoring`. Names, parameters and result shapes
/// follow the reference app; descriptions are written for Super Paste.
@MainActor
public struct MCPToolbox {
    public let store: ItemStoring

    public init(store: ItemStoring) { self.store = store }

    /// `read_item` returns at most this many characters of text (gap §22.3 #8: the reference's value wasn't recovered).
    public static let readTextLimit = ClipItem.previewTextLimit
    /// `read_item` scales images down to fit this many pixels on the longer side.
    public static let imageMaxPixels = 1024
    /// `search` returns at most this many items.
    public static let searchLimit = 100
    static let previewLength = 200

    /// A failed call: reported to the client as a tool result with `isError`, except `unknownTool`, which is a
    /// JSON-RPC error.
    public enum ToolError: Error, Equatable {
        case clipboardItemNotFound(String)
        case pinboardNotFound(String)
        case invalidName
        /// The full message.
        case invalidContent(String)
        /// The full message.
        case invalidDate(String)
        /// The full message (`badArgument` builds the "Invalid arguments: …" form).
        case invalidArguments(String)
        case unknownTool(String)
        /// The store couldn't save.
        case failed(String)

        static func badArgument(_ detail: String) -> ToolError { .invalidArguments("Invalid arguments: \(detail)") }

        public var message: String {
            switch self {
            case .clipboardItemNotFound(let id): "No clipboard item found with id \(id). Use search to find valid item ids."
            case .pinboardNotFound(let id): "No pinboard found with id \(id). Use list_pinboards to see valid ids."
            case .invalidName: "`name` cannot be empty."
            case .invalidContent(let message), .invalidDate(let message), .invalidArguments(let message), .failed(let message):
                message
            case .unknownTool(let name): "Unknown tool: \(name)"
            }
        }
    }

    /// A successful call: `structured` becomes `structuredContent`, `content` the content blocks.
    public struct Output {
        public var structured: JSON
        public var content: [JSON]

        init(_ structured: JSON, content: [JSON]? = nil) {
            self.structured = structured
            self.content = content ?? [["type": "text", "text": .string(structured.text)]]
        }
    }

    public func call(_ name: String, arguments: [String: JSON]) throws -> Output {
        guard let tool = Self.tools.first(where: { $0.name == name }) else { throw ToolError.unknownTool(name) }
        let args = try Arguments(arguments, allowed: tool.parameters)
        do {
            switch name {
            case "search": return try search(args)
            case "read_item": return try readItem(args)
            case "create_item": return try createItem(args)
            case "update_item": return try updateItem(args)
            case "delete_item": return try deleteItem(args)
            case "list_pinboards": return Output(["pinboards": .array(store.pinboards.map(summary))])
            case "create_pinboard": return try createPinboard(args)
            case "rename_pinboard": return try renamePinboard(args)
            case "delete_pinboard": return try deletePinboard(args)
            case "add_item_to_pinboard": return try pin(args, add: true)
            default: return try pin(args, add: false)
            }
        } catch let error as StoreError {
            switch error {
            case .itemNotFound(let id): throw ToolError.clipboardItemNotFound(id.uuidString)
            case .pinboardNotFound(let id): throw ToolError.pinboardNotFound(id.uuidString)
            case .invalidName: throw ToolError.invalidName
            case .invalidContent(let why): throw ToolError.invalidContent(why)
            case .database(let message): throw ToolError.failed(message)
            }
        }
    }

    // MARK: Items

    private func search(_ args: Arguments) throws -> Output {
        var query = SearchQuery(parsing: try args.string("query") ?? "")
        if let type = try args.string("type") {
            guard let filter = ItemTypeFilter(filterValue: type), Self.searchTypes.contains(filter.rawValue) else {
                throw ToolError.badArgument("`type` must be one of \(Self.searchTypes.joined(separator: ", ")).")
            }
            query = query.adding(.init(.type, filter.rawValue))
        }
        for (name, type) in [("app", SearchQuery.FilterType.app), ("device", .device), ("title", .title)] {
            if let value = try args.string(name)?.trimmingCharacters(in: .whitespaces), !value.isEmpty {
                query = query.adding(.init(type, value))
            }
        }
        if let id = try args.string("pinboard_id") {
            query = query.adding(.init(.pinboard, try pinboard(id).id.uuidString))
        }
        let from = try args.string("date_from")?.trimmingCharacters(in: .whitespaces)
        let to = try args.string("date_to")?.trimmingCharacters(in: .whitespaces)
        if from != nil || to != nil {
            let start = try from.map { try Self.dateBounds($0, name: "date_from").start }
            let end = try to.map { try Self.dateBounds($0, name: "date_to").end }
            if let start, let end, start >= end { throw ToolError.invalidDate("`date_from` must be before `date_to`.") }
            // The store reads "A..B" as from the start of A to the end of B (`DateRange.parse`).
            query = query.adding(.init(.date, "\(from ?? "")..\(to ?? "")"))
        }
        let limit = try args.int("limit") ?? 20
        guard limit >= 1 else { throw ToolError.badArgument("`limit` must be at least 1.") }
        let items = store.search(query, in: .all, limit: min(limit, Self.searchLimit), offset: 0)
        let hasMore = store.count(query, in: .all) > items.count
        return Output(["items": .array(items.map(summary)), "hasMore": .bool(hasMore)])
    }

    static let searchTypes = ["text", "image", "file", "color", "link"]

    /// What an ISO-8601 date (that whole day, in local time) or date-time (that instant) covers.
    static func dateBounds(_ value: String, name: String) throws -> (start: Date, end: Date) {
        if value.wholeMatch(of: #/\d{4}-\d{2}-\d{2}/#) != nil, let day = DateRange.parse(value), let start = day.start,
           let end = day.end {
            return (start, end)
        }
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let instant = plain.date(from: value) ?? fractional.date(from: value) else {
            throw ToolError.invalidDate("`\(name)` must be an ISO-8601 date or date-time: \(value)")
        }
        return (instant, instant)
    }

    private func readItem(_ args: Arguments) throws -> Output {
        let item = try item(try args.requiredString("id"))
        let id = JSON.string(item.id.uuidString)
        switch item.kind.typeFilter {
        case .text, .unknown:
            let full = fullText(of: item)
            let length = full.count
            let truncated = length > Self.readTextLimit
            let text = truncated ? String(full.prefix(Self.readTextLimit)) : full
            var structured: [String: JSON] = ["id": id, "type": .string(item.kind.typeFilter.rawValue), "text": .string(text),
                                              "truncated": .bool(truncated)]
            if truncated { structured["totalLength"] = .int(length) }
            return Output(.object(structured), content: [["type": "text", "text": .string(text)]])
        case .link:
            let url = item.link?.url ?? item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            var structured: [String: JSON] = ["id": id, "type": "link", "url": .string(url)]
            if let title = item.link?.title { structured["title"] = .string(title) }
            return Output(.object(structured), content: [["type": "text", "text": .string(url)]])
        case .color:
            let hex = TextClassifier.colorHex(in: item.text) ?? item.text
            return Output(["id": id, "type": "color", "color": .string(hex)], content: [["type": "text", "text": .string(hex)]])
        case .file:
            let paths = item.filePaths.joined(separator: "\n")
            return Output(["id": id, "type": "file", "paths": .array(item.filePaths.map { .string($0) })],
                          content: [["type": "text", "text": .string(paths)]])
        case .image:
            guard let image = encodedImage(of: item) else {
                throw ToolError.failed("The image's data isn't available on this Mac.")
            }
            let structured: JSON = ["id": id, "type": "image", "mimeType": .string(image.mimeType),
                                    "width": .int(image.size.width), "height": .int(image.size.height)]
            return Output(structured, content: [
                ["type": "image", "data": .string(image.data.base64EncodedString()), "mimeType": .string(image.mimeType)],
            ])
        }
    }

    /// The item's whole plain text: its `public.utf8-plain-text` representations, else the stored preview.
    private func fullText(of item: ClipItem) -> String {
        let texts = item.payload.compactMap { $0.rep(PasteboardType.plainText) }.compactMap { store.data(for: $0.blob) }
            .map { String(decoding: $0, as: UTF8.self) }
        if !texts.isEmpty { return texts.joined(separator: "\n") }
        if item.text.isEmpty && item.kind == .unknown {
            return "This item has no text. Its types: " + Set(item.payload.flatMap { $0.reps.map(\.type) }).sorted().joined(separator: ", ")
        }
        return item.text
    }

    /// The item's image scaled to fit `imageMaxPixels`, as PNG when it has transparency and JPEG otherwise.
    private func encodedImage(of item: ClipItem) -> (data: Data, mimeType: String, size: PixelSize)? {
        let reps = item.payload.flatMap(\.reps).filter { UTType($0.type)?.conforms(to: .image) == true }
        let sources = reps.map(\.blob) + [item.thumbnail].compactMap { $0 }
        for blob in sources {
            guard let data = store.data(for: blob), let source = CGImageSourceCreateWithData(data as CFData, nil) else { continue }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Self.imageMaxPixels,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { continue }
            let opaque = [.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
            let type = opaque ? UTType.jpeg : UTType.png
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { continue }
            return (output as Data, type.preferredMIMEType ?? "image/png", PixelSize(width: image.width, height: image.height))
        }
        return nil
    }

    private func createItem(_ args: Arguments) throws -> Output {
        let content = try args.requiredString("content")
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolError.invalidContent("`content` cannot be empty.")
        }
        let draft: ClipDraft
        if let listID = try args.string("list_id") {
            draft = .text(content, copiedAt: nil, pinboardID: try pinboard(listID).id)
        } else {
            draft = .text(content)
        }
        return Output(summary(try store.insert(draft).item))
    }

    private func updateItem(_ args: Arguments) throws -> Output {
        let item = try item(try args.requiredString("id"))
        let title = try args.string("title"), content = try args.string("content")
        guard title != nil || content != nil else {
            throw ToolError.invalidArguments("Pass at least one of `title` or `content` to update.")
        }
        if let content {
            guard item.kind != .image && item.kind != .files else {
                throw ToolError.invalidContent("Cannot edit the content of an image or file item. You can still change its title.")
            }
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ToolError.invalidContent("`content` cannot be empty.")
            }
            try store.replaceContent(of: item.id, with: .text(content))
        }
        if let title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            try store.rename(item.id, to: trimmed.isEmpty ? nil : trimmed)
        }
        return Output(summary(store.item(item.id) ?? item))
    }

    private func deleteItem(_ args: Arguments) throws -> Output {
        let item = try item(try args.requiredString("id"))
        guard try args.bool("confirm") == true else {
            return Output(["deleted": false, "item": summary(item), "message":
                "Preview — would delete this item from history and its pinboard, for good. Call again with confirm: true to delete."])
        }
        try store.delete([item.id])
        return Output(["deleted": true, "item": summary(item), "message": "Deleted item."])
    }

    // MARK: Pinboards

    private func createPinboard(_ args: Arguments) throws -> Output {
        let name = try args.requiredString("name").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ToolError.invalidName }
        // The first colour no pinboard uses yet, else round the palette.
        let used = Set(store.pinboards.map(\.color))
        let color = PinboardColor.allCases.first { !used.contains($0) }
            ?? PinboardColor.allCases[store.pinboards.count % PinboardColor.allCases.count]
        return Output(summary(try store.createPinboard(name: name, color: color)))
    }

    private func renamePinboard(_ args: Arguments) throws -> Output {
        var board = try pinboard(try args.requiredString("id"))
        let name = try args.requiredString("name").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ToolError.invalidName }
        board.name = name
        try store.updatePinboard(board)
        return Output(summary(store.pinboards.first { $0.id == board.id } ?? board))
    }

    private func deletePinboard(_ args: Arguments) throws -> Output {
        let board = try pinboard(try args.requiredString("id"))
        let before = summary(board)
        guard try args.bool("confirm") == true else {
            let count = store.count(.empty, in: .pinboard(board.id))
            let message = "Preview — would delete pinboard \"\(board.name)\" (\(count) item\(count == 1 ? "" : "s")). "
                + "Call again with confirm: true to delete. Items that are also in the clipboard history stay there; "
                + "items that live only in this pinboard are deleted with it."
            return Output(["deleted": false, "pinboard": before, "message": .string(message)])
        }
        try store.deletePinboard(board.id)
        return Output(["deleted": true, "pinboard": before, "message": .string("Deleted pinboard \"\(board.name)\".")])
    }

    private func pin(_ args: Arguments, add: Bool) throws -> Output {
        let item = try item(try args.requiredString("item_id"))
        let board = try pinboard(try args.requiredString("pinboard_id"))
        if add { try store.assign([item.id], to: board.id) } else { try store.unassign([item.id], from: board.id) }
        return Output(summary(board))
    }

    // MARK: Lookups and summaries

    private func item(_ id: String) throws -> ClipItem {
        guard let uuid = UUID(uuidString: id.trimmingCharacters(in: .whitespaces)), let item = store.item(uuid) else {
            throw ToolError.clipboardItemNotFound(id)
        }
        return item
    }

    private func pinboard(_ id: String) throws -> Pinboard {
        guard let uuid = UUID(uuidString: id.trimmingCharacters(in: .whitespaces)),
              let board = store.pinboards.first(where: { $0.id == uuid }) else { throw ToolError.pinboardNotFound(id) }
        return board
    }

    /// `MCPItem`: `{id, type, preview, timestamp?, app?, device?}`; `timestamp` is when it entered the history.
    func summary(_ item: ClipItem) -> JSON {
        var o: [String: JSON] = ["id": .string(item.id.uuidString), "type": .string(item.kind.typeFilter.rawValue),
                                 "preview": .string(preview(item))]
        if let copiedAt = item.copiedAt { o["timestamp"] = .string(Self.timestamp(copiedAt)) }
        if let app = item.sourceApp?.name { o["app"] = .string(app) }
        if let device = item.device?.name { o["device"] = .string(device) }
        return .object(o)
    }

    /// `MCPPinboard`: `{id, name, itemCount}`.
    func summary(_ board: Pinboard) -> JSON {
        ["id": .string(board.id.uuidString), "name": .string(board.name),
         "itemCount": .int(store.count(.empty, in: .pinboard(board.id)))]
    }

    /// A one-line description of the content, led by the user's title when there is one.
    private func preview(_ item: ClipItem) -> String {
        let body: String
        switch item.kind.typeFilter {
        case .text, .unknown:
            body = item.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        case .link:
            let url = item.link?.url ?? item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            body = item.link?.title.map { "\($0) — \(url)" } ?? url
        case .color:
            body = TextClassifier.colorHex(in: item.text) ?? item.text
        case .image:
            body = item.imageSize.map { "Image \($0.width)×\($0.height)" } ?? "Image"
        case .file:
            body = item.filePaths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
        }
        let line = item.title.map { body.isEmpty ? $0 : "\($0) — \(body)" } ?? body
        return line.count > Self.previewLength ? String(line.prefix(Self.previewLength - 1)) + "…" : line
    }

    static func timestamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}

/// Tool arguments with type checks; unknown names are refused so a misspelt filter doesn't silently match everything.
private struct Arguments {
    let values: [String: JSON]

    init(_ values: [String: JSON], allowed: [String]) throws {
        if let unknown = values.keys.sorted().first(where: { !allowed.contains($0) }) {
            throw MCPToolbox.ToolError.badArgument("unknown argument `\(unknown)`.")
        }
        self.values = values.filter { !$0.value.isNull }
    }

    func string(_ name: String) throws -> String? {
        guard let value = values[name] else { return nil }
        guard let s = value.string else { throw MCPToolbox.ToolError.badArgument("`\(name)` must be a string.") }
        return s
    }

    func requiredString(_ name: String) throws -> String {
        guard let s = try string(name) else { throw MCPToolbox.ToolError.badArgument("`\(name)` is required.") }
        return s
    }

    func bool(_ name: String) throws -> Bool? {
        guard let value = values[name] else { return nil }
        guard let b = value.bool else { throw MCPToolbox.ToolError.badArgument("`\(name)` must be true or false.") }
        return b
    }

    func int(_ name: String) throws -> Int? {
        guard let value = values[name] else { return nil }
        guard let i = value.int else { throw MCPToolbox.ToolError.badArgument("`\(name)` must be an integer.") }
        return i
    }
}
