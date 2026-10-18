# MCP server reference

Super Paste includes a [Model Context Protocol](https://modelcontextprotocol.io) server so that editors, assistants
and scripts on your Mac can search and read your clipboard history, save new items and organise pinboards, with your
approval. This document covers setup, the security model, every tool with its parameters and results, and the stdio
bridge. The user-facing summary is in the [README](../README.md#mcp-server-for-developers).

- [Enabling the server](#enabling-the-server)
- [Connecting a client](#connecting-a-client)
- [Security model](#security-model)
- [Conventions](#conventions)
- [Tools](#tools)
  - [search](#search) · [read_item](#read_item) · [create_item](#create_item) · [update_item](#update_item) · [delete_item](#delete_item)
  - [list_pinboards](#list_pinboards) · [create_pinboard](#create_pinboard) · [rename_pinboard](#rename_pinboard) · [delete_pinboard](#delete_pinboard) · [add_item_to_pinboard](#add_item_to_pinboard) · [remove_item_from_pinboard](#remove_item_from_pinboard)
- [Errors](#errors)
- [The stdio bridge](#the-stdio-bridge)
- [Protocol details](#protocol-details)

## Enabling the server

Settings → Integrations → **Enable MCP**. The server listens on `http://127.0.0.1:39725/mcp`; change the port in the
same pane (changing it disconnects and removes every connected client). The server starts with the app whenever the
switch is on and stops when you quit.

## Connecting a client

**Clients that sign in through the browser.** Most MCP clients support OAuth: give them the URL and they register
themselves, open Super Paste's consent page in your browser, and get a token after you approve. Nothing to copy.

```json
{
  "mcpServers": {
    "super-paste": { "url": "http://127.0.0.1:39725/mcp" }
  }
}
```

The consent page names the client as it registered itself. **Connect** approves it; **Cancel** denies it. Either way
the browser is sent back to the client.

**Clients that launch servers as commands.** Choose **Add Client…** in Settings → Integrations. Super Paste creates a
token, shows it once, and shows a configuration for the bundled stdio bridge:

```json
{
  "mcpServers": {
    "super-paste": {
      "command": "/Applications/Super Paste.app/Contents/MacOS/super-paste-mcp",
      "env": {
        "MCP_URL": "http://127.0.0.1:39725/mcp",
        "MCP_TOKEN": "<the token>"
      }
    }
  }
}
```

**Managing clients.** Settings → Integrations lists every connected client with how it connected (signed in or
token) and when it last called. **Disconnect…** revokes it immediately, including any open sessions.

## Security model

- **Off by default.** The server only runs while Enable MCP is on.
- **Loopback only.** It binds to `127.0.0.1`. Every request must name this server in its `Host` header
  (`127.0.0.1` or `localhost` with the bound port), and a request that carries an `Origin` must come from this
  server's own origin. Anything else is refused before routing, which defeats DNS rebinding and cross-site requests
  from web pages.
- **Consent.** A client can only get a token by being approved on the consent page (OAuth 2.1 authorization code
  with PKCE S256, dynamic client registration per RFC 7591, metadata per RFC 8414 and RFC 9728) or by being added by
  hand in Settings. Redirect URIs are limited to `https` anywhere, `http` on this Mac (loopback redirects, RFC 8252)
  and private-use schemes of native apps; never `javascript:`, `data:` or `file:`.
- **Tokens** are random, shown once, and stored only as hashes. `/mcp` requires `Authorization: Bearer <token>`.
  Sessions (`Mcp-Session-Id`) belong to the client that opened them.
- **The consent page** carries no script, allows only its own inline style through a per-response nonce, can't be
  framed, and may only post back to the server and redirect to the client.
- **Nothing is ever written to your system clipboard** by any tool. Deletions are two-step.
- **What a client does with what it reads is up to that client.** An assistant may send item text to its provider.
  Disconnect any client you no longer trust.

## Conventions

- All ids are UUID strings. Item ids come from `search`; pinboard ids from `list_pinboards`.
- Timestamps are ISO-8601 strings in UTC, e.g. `2026-10-18T09:41:00Z`.
- Every tool returns `structuredContent` (the JSON documented below) and a matching text `content` block, so
  clients that read either work. `read_item` of an image returns an `image` content block.
- Item summaries, used everywhere an item is returned:

  ```json
  {
    "id": "6F0B3F0E-…",
    "type": "text",
    "preview": "Rua Garrett 73, 1200-203 Lisboa",
    "timestamp": "2026-10-18T09:38:12Z",
    "app": "Notes",
    "device": "Studio"
  }
  ```

  `type` is one of `text`, `link`, `image`, `file`, `color`, `unknown`. `preview` is at most 200 characters.
  `timestamp` is when the item entered the history and is absent for items that live only in a pinboard. `app` and
  `device` are absent when unknown.
- Pinboard summaries: `{ "id": "…", "name": "Work", "itemCount": 12 }`.
- The server advertises these annotations per tool: `readOnlyHint`, `destructiveHint`, `idempotentHint`, and
  `openWorldHint: false` on all of them.

## Tools

### search

Searches everything saved: the clipboard history and all pinboards together. Without arguments it returns the most
recent items. Read-only, idempotent.

| Parameter | Type | Required | Meaning |
|---|---|---|---|
| `query` | string | no | Free text matched against titles and content by word prefix, ignoring case and diacritics. The strip's filter syntax works too (`app:Mail type:link "exact phrase"`). |
| `type` | string | no | One of `text`, `image`, `file`, `color`, `link`. |
| `app` | string | no | Only items copied from this app, as shown in the `app` field of results (name by prefix, or an exact bundle id). |
| `device` | string | no | Only items copied on this Mac, as shown in the `device` field. |
| `title` | string | no | Only items whose user-given title contains this text. |
| `pinboard_id` | string | no | Only items pinned to this pinboard. |
| `date_from` | string | no | Start of the range, inclusive, ISO-8601. A date alone (`2026-05-01`) starts at the beginning of that day. |
| `date_to` | string | no | End of the range. A date-time is exclusive; a date alone includes that whole day. |
| `limit` | integer | no | 1–100, default 20. |

Filters combine with AND. The range applies to `timestamp` (or the creation time for pinned-only items).
`date_from` must be before `date_to`.

Result:

```json
{ "items": [ { "id": "…", "type": "link", "preview": "https://www.airbnb.com/rooms/48213", "timestamp": "…", "app": "Safari", "device": "Studio" } ],
  "hasMore": true }
```

Newest first. `hasMore` is true when more items match than were returned; narrow the search or move the date
range to reach older ones. Unknown arguments are rejected.

Examples:

```json
{ "query": "offsite", "type": "link", "date_from": "2026-10-01" }
{ "app": "Terminal", "limit": 50 }
{ "pinboard_id": "2B6C…", "title": "invoice" }
```

### read_item

Returns an item's full content by id. Read-only, idempotent.

| Parameter | Type | Required |
|---|---|---|
| `id` | string | yes |

Result by type:

| Type | `structuredContent` | `content` |
|---|---|---|
| `text`, `unknown` | `{ "id", "type", "text", "truncated": false }`; when the text is longer than 20 000 characters, the first 20 000 with `"truncated": true` and `"totalLength"` | the text |
| `link` | `{ "id", "type": "link", "url", "title"? }` | the URL |
| `color` | `{ "id", "type": "color", "color": "#FF6B35" }` | the hex value |
| `file` | `{ "id", "type": "file", "paths": [ "…" ] }` | one path per line |
| `image` | `{ "id", "type": "image", "mimeType", "width", "height" }` | an `image` block: the image scaled to at most 1024 px on its longer side, re-encoded as JPEG (opaque) or PNG (with alpha), base64 |

Text comes back exactly as saved. If an image's data is missing on this Mac (for example, synced metadata whose
blob hasn't arrived), the call fails with an explanation.

### create_item

Saves text as a new item. Never touches the system clipboard. Not idempotent: each call creates (or pins) again.

| Parameter | Type | Required | Meaning |
|---|---|---|---|
| `content` | string | yes | Stored exactly as given; must not be blank. |
| `list_id` | string | no | A pinboard id. The item is pinned there instead of going into the history. If the same content is already in the history, that item is pinned and stays in the history; otherwise a new item is created that lives only in the pinboard. |

The type is detected from the content: usually `text`; a six-digit hex colour such as `#FF0000` becomes `color`,
and a URL becomes `link`. Returns the item summary (`timestamp` absent for a pinned-only item).

```json
{ "content": "Thanks for the invoice. It's been approved and will be paid within 14 days.", "list_id": "2B6C…" }
```

### update_item

Changes an item's title, its content, or both. Idempotent.

| Parameter | Type | Required | Meaning |
|---|---|---|---|
| `id` | string | yes | |
| `title` | string | one of the two | The new title; an empty string clears it. |
| `content` | string | one of the two | Replaces the text and detects the type again, as `create_item` does. Not allowed for image and file items (their title can still change). |

Returns the updated summary.

### delete_item

Deletes an item for good, from the history and from every pinboard. Two steps. Destructive.

| Parameter | Type | Required | Meaning |
|---|---|---|---|
| `id` | string | yes | |
| `confirm` | boolean | no | Leave it out (or `false`) to preview; `true` deletes. |

Preview result: `{ "deleted": false, "item": <summary>, "message": "Preview — would delete this item from history and its pinboard, for good. Call again with confirm: true to delete." }`
After deletion: `{ "deleted": true, "item": <summary>, "message": "Deleted item." }`

To unpin without deleting, use `remove_item_from_pinboard`.

### list_pinboards

No parameters. Read-only. Returns `{ "pinboards": [ { "id", "name", "itemCount" } ] }` in the user's tab order.

### create_pinboard

| Parameter | Type | Required | Meaning |
|---|---|---|---|
| `name` | string | yes | Surrounding whitespace is removed; must not be empty. |

The new board gets the first colour no board uses yet. Returns its summary.

### rename_pinboard

| Parameter | Type | Required |
|---|---|---|
| `id` | string | yes |
| `name` | string | yes |

Returns the updated summary. Idempotent.

### delete_pinboard

Two steps, like `delete_item`. Items that are also in the history stay there; pinned-only items are removed with the
board.

| Parameter | Type | Required |
|---|---|---|
| `id` | string | yes |
| `confirm` | boolean | no |

Preview: `{ "deleted": false, "pinboard": <summary>, "message": "Preview — would delete pinboard \"Work\" (12 items). Call again with confirm: true to delete. Pinned items stay in clipboard history." }`

### add_item_to_pinboard

| Parameter | Type | Required |
|---|---|---|
| `item_id` | string | yes |
| `pinboard_id` | string | yes |

Pins an item; adding one that's already there changes nothing. Returns the pinboard's updated summary. Idempotent.

### remove_item_from_pinboard

Same parameters. Unpins without deleting: an item in the history stays there; one that lived only in this pinboard
moves to the history. Returns the pinboard's updated summary. Idempotent.

## Errors

Tool failures come back as MCP tool errors (`isError: true`) with one of these messages:

| Situation | Message |
|---|---|
| Unknown item id | `No clipboard item found with id <id>. Use search to find valid item ids.` |
| Unknown pinboard id | `No pinboard found with id <id>. Use list_pinboards to see valid ids.` |
| Empty name | `` `name` cannot be empty. `` |
| Empty content | `` `content` cannot be empty. `` |
| Editing an image or file's content | `Cannot edit the content of an image or file item. You can still change its title.` |
| Bad `type` | `` Invalid arguments: `type` must be one of text, image, file, color, link. `` |
| Bad date | `` `date_from` must be an ISO-8601 date or date-time: <value> `` · `` `date_from` must be before `date_to`. `` |
| Bad `limit` | `` Invalid arguments: `limit` must be at least 1. `` |
| Unknown argument | `` Invalid arguments: unknown argument `foo`. `` |
| Neither `title` nor `content` | `` Pass at least one of `title` or `content` to update. `` |
| Unknown tool | `Unknown tool: <name>` |
| Store failure | The database's own message |

HTTP-level failures: `401` with a `WWW-Authenticate: Bearer resource_metadata="…/.well-known/oauth-protected-resource/mcp"`
challenge when the token is missing or revoked; `403` for a wrong `Host` or `Origin`; `404` for an unknown session
(after Super Paste restarts); `405` for other methods on `/mcp` (`GET`, `POST`, `DELETE` are allowed); `413` for
oversized bodies.

## The stdio bridge

`super-paste-mcp` ships inside the app bundle (`Contents/MacOS/super-paste-mcp`) for clients that can only run MCP
servers as a command. It reads newline-delimited JSON-RPC from stdin, POSTs each message to `MCP_URL` with
`Authorization: Bearer $MCP_TOKEN`, and writes every reply (plain JSON or SSE `data:` events) to stdout, one JSON
message per line.

- `MCP_URL` must be `http://127.0.0.1:<port>/mcp` (or `localhost`, `::1`), or an `https` URL; the token is never
  sent anywhere else.
- When Super Paste restarts, its sessions are gone; the bridge replays the client's `initialize` once and retries,
  so the client doesn't notice.
- An HTTP failure for a request comes back as a JSON-RPC error with the same id, so a client never waits for an
  answer that won't arrive.
- At the end of stdin the bridge closes the session (`DELETE`) and exits. Exit code 64 means the environment is
  missing or malformed.

## Protocol details

- Transport: MCP Streamable HTTP at `/mcp`. `POST` carries JSON-RPC; replies are JSON or SSE depending on the
  client's `Accept`. The first `initialize` reply sets `Mcp-Session-Id`; `DELETE /mcp` ends a session.
- `initialize` returns the server's `instructions`: "Super Paste is a clipboard manager for macOS. These tools search
  and read the user's clipboard history, save new items and organise pinboards on the user's behalf."
- Discovery: `GET /.well-known/oauth-protected-resource` (and `…/mcp`) per RFC 9728 and
  `GET /.well-known/oauth-authorization-server` per RFC 8414, both relative to the server's base URL.
- OAuth endpoints: `POST /register` (RFC 7591), `GET`/`POST /authorize` (the consent page), `POST /token`
  (`authorization_code` with PKCE `S256` only, `code_challenge_methods_supported: ["S256"]`), `POST /revoke`.
  Token endpoint auth methods: `none`, `client_secret_post`, `client_secret_basic`. Registered clients get
  `client_secret_expires_at: 0` (never).
- Request bodies are capped (larger for `/mcp` than for the OAuth endpoints); a repeated `Content-Length` or `Host`
  header is rejected as a smuggling attempt.
