# Known blockers and owner decisions

## Blocked on credentials (cannot be done on this Mac)

- No Apple Distribution / 3rd Party Mac Developer Application or Installer identity, no Mac App Store provisioning
  profile, no Xcode: the Store `.pkg` has not been signed, validated or uploaded. `package-appstore.sh` is written
  but its signed path has never run. Register `com.udsy.superpaste.appstore` (and decide whether the helper needs its
  own App ID `com.udsy.superpaste.appstore.mcp` — see below), create the profile, then run it.
- Direct edition Developer ID signing + notarization: not done (no Developer ID certificate); the direct release
  scripts are unchanged and still ship the self-signed DMG.

## Needs a human run

See `test-results.md` › "Needs a human run": global shortcut, strip and Return, hot corner, ignored-apps exclusion,
copied-file paste after relaunch, sandboxed sync folder picker + relaunch, direct paste after granting post-event
access, Import through the panel, Claude Desktop launching the bridge, Open at login. Results observed earlier with
synthetic input are not counted.

## Risks for review

- **Direct paste (2.4.5, "Accessibility for non-accessibility purposes")** has drawn rejections for similar apps.
  Mitigated: off by default, copy-to-clipboard works fully, review notes explain the single use.
- **Sandboxed command-line helper launched by other apps.** The bridge is not a child of the app, so it has its own
  sandbox and an embedded Info.plist. App Store validation of such a helper (whether it needs its own App ID /
  profile or `application-identifier`) is unverified — only real validation will tell. Fallback if rejected: drop
  the bridge from the Store build; clients that connect by URL (OAuth) keep working.
- Signing on a distribution identity may change behaviour seen with ad-hoc signing (hot corner monitor, TCC); re-run
  test-results §3–§8 on the signed build.

## Material product changes needing owner approval

1. Store edition defaults **Paste items to "To clipboard"** (direct edition: "To active app").
2. Store edition has **no updater** and no "Install updates automatically" row; About shows "Import from Super
   Paste (direct download)" instead.
3. Store edition **can't detect a macOS Hot Corner on the same corner** (Dock prefs unreadable sandboxed).
4. Copied files captured **before** this change or **imported** from the direct edition have no bookmark: choosing
   them pastes nothing for the file (the sandbox drops the URL). Re-copying the file fixes it. Owner may prefer a
   fallback that pastes the path as text.
5. **Import** needs a quit and reopen; preferences and MCP clients are not imported, sync starts over, and a
   history containing symbolic links is refused. TCC grants
   (pasteboard, Accessibility) must be given again for the new bundle id.
6. Both editions use MCP port 39725 by default; running both means changing one.
7. **Export compliance** answer for the sync encryption (AES-256-GCM).
8. Price and final bundle id.
