import Foundation

/// What `tools/list` advertises (behaviour.md §14.2, strings.md "MCP server"). Parameter names are the reference
/// app's; the wording is Super Paste's own.
struct MCPToolDefinition {
    var name: String
    var title: String
    var description: String
    /// Parameter name → (JSON Schema, required).
    var properties: [(String, JSON, Bool)]
    var readOnly: Bool
    var destructive: Bool
    var idempotent: Bool

    var parameters: [String] { properties.map(\.0) }

    var json: JSON {
        var schema: [String: JSON] = [
            "type": "object",
            "properties": .object(Dictionary(uniqueKeysWithValues: properties.map { ($0.0, $0.1) })),
            "additionalProperties": false,
        ]
        let required = properties.filter(\.2).map { JSON.string($0.0) }
        if !required.isEmpty { schema["required"] = .array(required) }
        return [
            "name": .string(name),
            "title": .string(title),
            "description": .string(description),
            "inputSchema": .object(schema),
            "annotations": [
                "title": .string(title), "readOnlyHint": .bool(readOnly), "destructiveHint": .bool(destructive),
                "idempotentHint": .bool(idempotent), "openWorldHint": false,
            ],
        ]
    }
}

private func string(_ description: String) -> JSON { ["type": "string", "description": .string(description)] }

extension MCPToolbox {
    /// The server's `instructions` in `initialize`.
    static let instructions = "Super Paste is a clipboard manager for macOS. These tools search and read the user's "
        + "clipboard history, save new items and organise pinboards on the user's behalf."

    static let tools: [MCPToolDefinition] = [
        MCPToolDefinition(
            name: "search", title: "Search saved items",
            description: """
            Searches everything the user saved: clipboard history and pinboards together. Without arguments it \
            returns the most recent items. `query` is free text matched against titles and content (the strip's \
            filter syntax, such as app:Mail, works too). Optional filters combine: `type`; `app` and `device` (as \
            shown in the `app` and `device` fields of results); `pinboard_id` (from list_pinboards); `title` (part \
            of an item's title); `date_from` and `date_to` (ISO-8601, a half-open range on `timestamp`; either end \
            may be left out). Returns short summaries (id, type, preview, timestamp, app, device), newest first, \
            plus `hasMore`; `timestamp` is when the item entered the history and is absent for items that live only \
            in a pinboard. Use read_item for the full content. At most \(MCPToolbox.searchLimit) of the most recent \
            matches are returned, so narrow the search to reach older items.
            """,
            properties: [
                ("query", string("Free text matched against item titles and content."), false),
                ("type", ["type": "string", "enum": .array(MCPToolbox.searchTypes.map { .string($0) }),
                          "description": "Only items of this type."], false),
                ("app", string("Only items copied from this app (the `app` field of results)."), false),
                ("device", string("Only items copied on this device (the `device` field of results)."), false),
                ("title", string("Only items whose title contains this text."), false),
                ("pinboard_id", string("Only items pinned to this pinboard (an id from list_pinboards)."), false),
                ("date_from", string("""
                    Start of the time range, inclusive, as ISO-8601, e.g. 2026-05-01T00:00:00Z. A date alone \
                    (2026-05-01) starts at the beginning of that day.
                    """), false),
                ("date_to", string("""
                    End of the time range as ISO-8601. A date-time is exclusive; a date alone (2026-05-01) includes \
                    that whole day.
                    """), false),
                ("limit", ["type": "integer", "minimum": 1, "maximum": .int(MCPToolbox.searchLimit), "default": 20,
                           "description": .string("How many items to return: 20 unless given, at most \(MCPToolbox.searchLimit).")], false),
            ],
            readOnly: true, destructive: false, idempotent: true),
        MCPToolDefinition(
            name: "read_item", title: "Read saved item",
            description: """
            Returns the full content of a saved item by id (from search). Text comes back exactly as saved, cut at \
            \(MCPToolbox.readTextLimit) characters when longer (the structured result then has `truncated` and \
            `totalLength`); a link returns its URL; a colour its #RRGGBB value; files their paths, one per line; an \
            image comes back as the image itself, scaled down and re-encoded, for clients that can see images.
            """,
            properties: [("id", string("The item's id (from search)."), true)],
            readOnly: true, destructive: false, idempotent: true),
        MCPToolDefinition(
            name: "create_item", title: "Create clipboard item",
            description: """
            Saves text `content` as a new item. Without `list_id` it goes into the clipboard history and shows up in \
            search. With `list_id` (a pinboard id) it is pinned there instead: when the same content is already in \
            the history, that item is pinned (and stays in the history); otherwise a new item is created that lives \
            only in the pinboard. Never touches the system clipboard. The type is detected from the content: \
            usually `text`, but a six-digit hex colour such as "#FF0000" becomes a `color` and a URL a `link`. \
            Returns the item's summary (id, type, preview, timestamp, app, device); `timestamp` is absent when the \
            item lives only in a pinboard.
            """,
            properties: [
                ("content", string("The text to save, stored exactly as given."), true),
                ("list_id", string("""
                    Optional pinboard id from list_pinboards. The item is pinned there instead of going into the \
                    history; content already in the history is pinned rather than duplicated.
                    """), false),
            ],
            readOnly: false, destructive: false, idempotent: false),
        MCPToolDefinition(
            name: "update_item", title: "Update saved item",
            description: """
            Changes a saved item's `title`, its `content`, or both (at least one is required). A `title` sets the \
            title; an empty string clears it. A `content` replaces the text and detects the type again, as \
            create_item does. Image and file items can't have their content changed, only their title. Returns the \
            updated summary.
            """,
            properties: [
                ("id", string("The item's id (from search)."), true),
                ("title", string("The new title; an empty string clears it."), false),
                ("content", string("The new text; replaces the content and detects the type again."), false),
            ],
            readOnly: false, destructive: false, idempotent: true),
        MCPToolDefinition(
            name: "delete_item", title: "Delete saved item",
            description: """
            Deletes a saved item for good, from the clipboard history and from every pinboard it is pinned to. Two \
            steps: without `confirm` nothing changes and the result describes what would be deleted; call again \
            with `confirm: true` to delete. To only unpin an item and keep it, use remove_item_from_pinboard.
            """,
            properties: [
                ("id", string("The item's id (from search)."), true),
                ("confirm", ["type": "boolean", "description": "true deletes; leave it out (or false) to preview."], false),
            ],
            readOnly: false, destructive: true, idempotent: false),
        MCPToolDefinition(
            name: "list_pinboards", title: "List pinboards",
            description: """
            Lists the user's pinboards as short summaries (id, name, itemCount). Use an id with \
            add_item_to_pinboard, remove_item_from_pinboard, rename_pinboard, delete_pinboard or search.
            """,
            properties: [], readOnly: true, destructive: false, idempotent: true),
        MCPToolDefinition(
            name: "create_pinboard", title: "Create pinboard",
            description: "Creates a pinboard with the given name. Returns its summary (id, name, itemCount).",
            properties: [("name", string("The pinboard's name; surrounding whitespace is removed."), true)],
            readOnly: false, destructive: false, idempotent: false),
        MCPToolDefinition(
            name: "rename_pinboard", title: "Rename pinboard",
            description: "Renames a pinboard. Returns its updated summary.",
            properties: [
                ("id", string("The pinboard's id (from list_pinboards)."), true),
                ("name", string("The new name; surrounding whitespace is removed."), true),
            ],
            readOnly: false, destructive: false, idempotent: true),
        MCPToolDefinition(
            name: "delete_pinboard", title: "Delete pinboard",
            description: """
            Deletes a pinboard. Two steps: without `confirm` nothing changes and the result describes what would be \
            deleted; call again with `confirm: true` to delete. Items that are also in the clipboard history stay \
            there.
            """,
            properties: [
                ("id", string("The pinboard's id (from list_pinboards)."), true),
                ("confirm", ["type": "boolean", "description": "true deletes; leave it out (or false) to preview."], false),
            ],
            readOnly: false, destructive: true, idempotent: false),
        MCPToolDefinition(
            name: "add_item_to_pinboard", title: "Add item to pinboard",
            description: """
            Pins an item to a pinboard. Adding an item that is already there changes nothing. Returns the \
            pinboard's updated summary.
            """,
            properties: [
                ("item_id", string("The item's id (from search)."), true),
                ("pinboard_id", string("The pinboard's id (from list_pinboards)."), true),
            ],
            readOnly: false, destructive: false, idempotent: true),
        MCPToolDefinition(
            name: "remove_item_from_pinboard", title: "Remove item from pinboard",
            description: """
            Unpins an item from a pinboard. Nothing is deleted: an item in the clipboard history stays there, and \
            one that lived only in this pinboard moves to the history. Returns the pinboard's updated summary.
            """,
            properties: [
                ("item_id", string("The item's id (from search)."), true),
                ("pinboard_id", string("The pinboard's id (from list_pinboards)."), true),
            ],
            readOnly: false, destructive: false, idempotent: true),
    ]
}
