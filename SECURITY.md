# Security Policy

Super Paste runs entirely on your Mac. It has no accounts, no analytics and no servers. Network access is limited to
automatic updates from GitHub Releases, link previews for links you copy, and end-to-end-encrypted sync through a
folder you choose, each with its own switch. The MCP server listens on `127.0.0.1` only and is off by default. The sync
key lives in the macOS Keychain; MCP tokens are stored only as hashes. An update is installed only if its SHA-256
matches the release notes and its code signature satisfies the running copy's designated requirement.

Areas where a report is especially valuable: the MCP server (OAuth with dynamic client registration and PKCE, the
consent page, Host and Origin checks, token handling, the stdio bridge), sync encryption and key handling, capture
filters for passwords and confidential content, the update verification and swap, and the `superpaste://` URL
scheme.

## Reporting a vulnerability

Please **do not** open a public issue. Use GitHub's
[private vulnerability reporting](https://github.com/udsy19/super-paste/security/advisories/new) instead.
You'll get a response within a few days, and a fix will be released as soon as practical.

## Supported versions

Only the latest release receives security fixes.
