# Paste 7.0.3 — English UI string table

Source of truth for every user-visible English string found in the installed app
(`/Applications/Setapp/Paste.app`, build 29869049). Companion to `behaviour.md`.

**Sources**

- **[R] Localizable** — `Contents/Resources/PastePackages_PasteLocalization.bundle/Contents/Resources/en.lproj/Localizable.strings` (536 keys) and `Localizable.stringsdict` (12 plural rules). This bundle is shared with Paste for iOS, so many keys never appear on the Mac.
- **[B] Hard-coded** — English literals compiled into the `Paste` binary (no localization key): App Intents, the MCP server, the hidden main menu, a few tooltips and search-filter labels. Literals of 15 bytes or less are stored as immediates in machine code; they were recovered by decoding `mov`/`movk` sequences, so a few short labels may be missing.
- **[R] Storyboard / plist** — `PasteStack.storyboardc`, `Info.plist`, `Metadata.appintents`.

**How to read the tables**

- Strings are copied verbatim. `\n` marks a line break in the source. Many strings contain non-breaking spaces (U+00A0) between words, which Paste uses to control line wrapping. They are kept as-is in the tables.
- `%@`, `%d`, `%%` are printf-style placeholders. `{icon:NAME}` is Paste's inline SF Symbol markup: a regex `\{([\w.]+):([\w:.]+)\}` in `PasteUI` swaps the token for an image attachment [B].
- **Super Paste** column:
  - `reuse` — Mac-relevant. Keep the short labels. Rewrite long prose in our own words and swap the brand ("Paste" → "Super Paste").
  - `iOS-only` — never shown on the Mac. Ignore.
  - `drop` — the feature is being dropped (licensing, iCloud sharing, review prompts, Paste 4→5 migration, marketing notifications).
- The grouping by screen is inferred from key prefixes plus call-site analysis of the binary (which view's code calls each localization accessor). See `behaviour.md` for where each string appears.

---

## Localizable.strings / .stringsdict, grouped by screen [R]

### Onboarding (macOS)

| Key | English (verbatim) | Super Paste |
|---|---|---|
| `onboarding.introduction.action.primary` | Get Started | reuse |
| `onboarding.macos.clipboard-history.subtitle` | How long to retain copied content | reuse |
| `onboarding.macos.clipboard-history.title` | Clipboard history | reuse |
| `onboarding.macos.clipboard-history.unlimited-tooltip` | Unlimited history may increase your disk space usage | reuse |
| `onboarding.macos.icloud-sync.subtitle` | Securely sync your data across all devices | reuse |
| `onboarding.macos.icloud-sync.title` | iCloud sync | reuse |
| `onboarding.macos.introduction.subtitle` | Paste is a time machine for your Clipboard that lets you instantly find anything you’ve ever copied and use it whenever you need it again. | reuse |
| `onboarding.macos.introduction.title` | A Better Way to Copy and Paste | reuse |
| `onboarding.macos.open-at-login.subtitle` | Open at login and always keep running | reuse |
| `onboarding.macos.open-at-login.title` | Run in background | reuse |
| `onboarding.macos.setup.subtitle` | Set up and start using Paste. | reuse |
| `onboarding.macos.setup.title` | Quick Start | reuse |
| `onboarding.macos.shortcut.subtitle` | Instantly access Paste in any app | reuse |
| `onboarding.macos.shortcut.title` | Activation shortcut | reuse |

### Onboarding initial content (welcome pinboard items)

| Key | English (verbatim) | Super Paste |
|---|---|---|
| `onboarding.content.getting-started.title` | Getting Started | reuse |
| `onboarding.content.getting-started.url-name` | Start using Paste | reuse |
| `onboarding.content.help-and-support.title` | Help and Support | reuse |
| `onboarding.content.help-and-support.url-name` | Explore Help Center | reuse |
| `onboarding.content.keep.body` | Reuse copied items across devices.\n\nTap an item to copy to clipboard and paste anywhere. | iOS-only |
| `onboarding.content.keep.macos.body` | Access and reuse anything you've copied on any device.\n\nActivate Paste using ⇧⌘V, select the items, and press the return key to paste them into any app. | reuse |
| `onboarding.content.keep.title` | Keep | reuse |
| `onboarding.content.organize.body` | Pin items for quick and easy access.\n\nLong-tap an item to see all available actions. | iOS-only |
| `onboarding.content.organize.macos.body` | Pin items to pinboards using the context menu or drag-and-drop.\n\nPinned items are not deleted when you clear your history and are always accessible across all devices. | reuse |
| `onboarding.content.organize.title` | Organize | reuse |
| `onboarding.content.paste-for-mac.title` | Paste for Mac | iOS-only |
| `onboarding.content.paste-for-mac.url-name` | Get Paste for Mac | iOS-only |
| `onboarding.content.search.body` | Search and filter by content or app.\n\nFind links from Mail like “mail link meeting slides”. | iOS-only |
| `onboarding.content.search.macos.body` | Start typing to search. Filter by content type or the source app.\n\nFor example, search for “mail link meeting slides” to find a link to the slides you copied from Mail. | reuse |
| `onboarding.content.search.title` | Search | reuse |
| `onboarding.content.stay-tuned.title` | Stay Tuned | reuse |
| `onboarding.content.stay-tuned.url-name` | Follow Paste on X | reuse |
| `onboarding.content.welcome-aboard.body` | We've pinned some links here for you.\n\nLong-tap a link and select Open from the context menu. | iOS-only |
| `onboarding.content.welcome-aboard.macos.body` | We've pinned a few links here to help you get the most out of Paste.\n\nTo open any link, select Open in the context menu or use ⌘O shortcut. | reuse |
| `onboarding.content.welcome-aboard.title` | Welcome Aboard | reuse |

### Permissions: Accessibility, Pasteboard access, Paste-to-other-apps prompt

| Key | English (verbatim) | Super Paste |
|---|---|---|
| `accessibility-access.enable-accessibility-access.allow-access` | Allow Access | reuse |
| `accessibility-access.enable-accessibility-access.help` | I'm Having an Issue | reuse |
| `accessibility-access.enable-accessibility-access.open-system-settings` | Open System Settings | reuse |
| `accessibility-access.enable-accessibility-access.skip` | Not Now | reuse |
| `accessibility-access.enable-accessibility-access.subtitle` | To paste directly into other apps, allow Paste to use the accessibility features of your Mac in System Settings. | reuse |
| `accessibility-access.enable-accessibility-access.title` | Paste to Any App | reuse |
| `accessibility-access.enable-pasteboard-access.subtitle` | Paste needs access to your clipboard to save what you copy and keep everything in sync automatically. | reuse |
| `accessibility-access.enable-pasteboard-access.title` | Allow Pasteboard Access | reuse |
| `accessibility-access.paste-to-other-apps.copy-to-clipboard` | Not Now, Copy to Clipboard | reuse |
| `accessibility-access.paste-to-other-apps.description` | Paste needs accessibility access to paste directly to other apps. | reuse |
| `accessibility-access.paste-to-other-apps.enable-accessibility-access` | Allow Accessibility Access | reuse |
| `accessibility-access.paste-to-other-apps.title` | Do you want to paste directly to %@? | reuse |

### Permissions: Screen Recording (Intelligent Clipboard)

| Key | English (verbatim) | Super Paste |
|---|---|---|
| `screen-recording-access.enable-screen-recording-access.action.help` | Help | reuse |
| `screen-recording-access.enable-screen-recording-access.action.open-system-settings` | Open System Settings | reuse |
| `screen-recording-access.enable-screen-recording-access.subtitle` | To get suggestions for what you’re about to paste, allow Paste to see your screen in System Settings. Everything stays on your Mac. | reuse |
| `screen-recording-access.enable-screen-recording-access.title` | Get Suggestions as You Paste | reuse |

### Settings: General pane

| Key | English (verbatim) | Super Paste |
|---|---|---|
| `settings.general.title` | General | reuse |
| `settings.history.forever` | Forever | reuse |
| `settings.history.title` | Keep History | reuse |
| `settings.menu-bar-icon.title` | Show in Menu Bar | reuse |
| `settings.open-at-login.title` | Open at login | reuse |
| `settings.paste-items.accessibility-access-request` | Allow Accessibility Access | reuse |
| `settings.paste-items.active-app.info` | Paste selected items directly to the application you are currently using. | reuse |
| `settings.paste-items.active-app.title` | To active app | reuse |
| `settings.paste-items.clipboard.info` | Copy selected items to the system clipboard to paste manually later. | reuse |
| `settings.paste-items.clipboard.title` | To clipboard | reuse |
| `settings.paste-items.plain-text.title` | Always paste as Plain Text | reuse |
| `settings.paste-items.title` | Paste Items | reuse |
| `settings.run-in-background.title` | Run in background | iOS-only |
| `settings.sound-effects.title` | Sound effects | reuse |

### Settings: iCloud sync rows (to be replaced by Folder Sync)

| Key | English (verbatim) | Super Paste |
|---|---|---|
| `settings.sync.disable-confirmation-sharing.message` | All shared pinboards will be deleted from all participants. Pinboards shared with you will be deleted from this device. | drop |
| `settings.sync.disable-confirmation.action.cancel` | Keep Sync On | reuse |
| `settings.sync.disable-confirmation.action.confirm` | Turn Sync Off | reuse |
| `settings.sync.disable-confirmation.message` | Your local and iCloud data remain unchanged. However, when you turn sync back on later, Paste will need some time to get in sync with iCloud. | reuse |
| `settings.sync.disable-confirmation.title` | Turn Sync Off? | reuse |
| `settings.sync.status.error.icloud-quota-exceeded` | iCloud storage quota exceeded | reuse |
| `settings.sync.status.error.icloud-unavailable` | iCloud account unavailable | reuse |
| `settings.sync.status.error.icloud-unknown` | iCloud error (code %@) | reuse |
| `settings.sync.status.error.network` | Network error | reuse |
| `settings.sync.status.last-sync` | Synced | reuse |
| `settings.sync.status.never` | never | reuse |
| `settings.sync.status.not-available` | Check your iCloud settings | reuse |
| `settings.sync.status.syncing` | Syncing | reuse |
| `settings.sync.title` | iCloud sync | reuse |

### Settings: Privacy pane

| Key | English (verbatim) | Super Paste |
|---|---|---|
| `settings.privacy.applications-history.empty` | No items | reuse |
| `settings.privacy.applications-history.subtitle` | Do not save content copied from the applications below. | reuse |
| `settings.privacy.applications-history.title` | Ignore Applications | reuse |
| `settings.privacy.autogenerated-content.subtitle` | Do not save temporary data generated by other apps. | reuse |
| `settings.privacy.autogenerated-content.title` | Ignore transient content | reuse |
| `settings.privacy.confidential-content.subtitle` | Do not save passwords and sensitive data when detected. | reuse |
| `settings.privacy.confidential-content.title` | Ignore confidential content | reuse |
| `settings.privacy.link-preview.subtitle` | Download web content for previews; may activate one-time or analytics-sensitive links. | reuse |
| `settings.privacy.link-preview.title` | Generate Link Previews | reuse |
| `settings.privacy.screensharing.subtitle` | Allow Paste to appear to others when you share your screen. | reuse |
| `settings.privacy.screensharing.title` | Show During Screen Sharing | reuse |
| `settings.privacy.title` | Privacy | reuse |

### Settings: Shortcuts pane

| Key | English (verbatim) | Super Paste |
|---|---|---|
| `settings.shortcuts.action.reset` | Reset shortcuts to default | reuse |
| `settings.shortcuts.action.reset.confirmation` | Are you sure you want to reset all shortcuts to their default values? | reuse |
| `settings.shortcuts.activate-paste-stack.title` | Activate Paste Stack | reuse |
| `settings.shortcuts.activate-paste.title` | Activate Paste | reuse |
| `settings.shortcuts.next-pinboard.title` | Show next Pinboard | reuse |
| `settings.shortcuts.plain-text.title` | Plain Text mode | reuse |
| `settings.shortcuts.previous-pinboard.title` | Show previous Pinboard | reuse |
| `settings.shortcuts.quick-paste.title` | Quick Paste | reuse |
| `settings.shortcuts.title` | Shortcuts | reuse |

### Shortcut recorder control

| Key | English (verbatim) | Super Paste |
|---|---|---|
| `shortcut-recorder.action.remove` | Remove | reuse |
| `shortcut-recorder.error.option-key` | Shortcuts using the Option key without Command or Control may not work correctly before macOS 15.2. Please consider updating to the latest version of macOS. | reuse |
| `shortcut-recorder.error.used-in-menu` | This shortcut cannot be used because it is already used by the menu item ‘%@’. | reuse |
| `shortcut-recorder.error.used-in-system` | This combination cannot be used because it is already used by a system-wide keyboard shortcut.\nIf you really want to use this key combination, most shortcuts can be changed in the Keyboard & Mouse panel in System Settings. | reuse |
| `shortcut-recorder.none` | None | reuse |
| `shortcut-recorder.status.recording` | Recording | reuse |
| `shortcut.space` | Space | reuse |

### Settings: Intelligence pane (Intelligent Clipboard + MCP)

| Key | English (verbatim) | Super Paste |
|---|---|---|
| `settings.intelligence.clipboard.enable.subtitle` | Get suggestions for what you’re about to paste, based on what you’re working on. Everything stays on your Mac. | reuse |
| `settings.intelligence.clipboard.enable.title` | Intelligent Clipboard | reuse |
| `settings.intelligence.clipboard.section.title` | Clipboard | reuse |
| `settings.intelligence.clipboard.unavailable.text` | Requires Apple Intelligence | reuse |
| `settings.intelligence.mcp.section.title` | MCP & AI tools | reuse |
| `settings.intelligence.title` | Intelligence | reuse |
| `settings.mcp.add-tool.cancel` | Cancel | reuse |
| `settings.mcp.add-tool.create` | Create | reuse |
| `settings.mcp.add-tool.name-placeholder` | Name (e.g. My AI Tool) | reuse |
| `settings.mcp.add-tool.title` | Add an AI Tool | reuse |
| `settings.mcp.connect.action.connect-to` | Connect AI Tool… | reuse |
| `settings.mcp.connect.cli-authentication-instruction` | Start command-line assistant, type /mcp, then select Paste and authenticate. | reuse |
| `settings.mcp.connect.cli-instruction` | Run this command in Terminal: | reuse |
| `settings.mcp.connect.config-instruction` | Add this to your app's MCP config, then approve Paste in your browser. | reuse |
| `settings.mcp.connect.deeplink-instruction` | %@ will open and ask you to confirm installing the Paste MCP. Then approve the connection in your browser. | reuse |
| `settings.mcp.connect.mcpb-instruction` | desktop assistant app will open. Install the Paste extension there to finish connecting. | reuse |
| `settings.mcp.connect.token-instruction` | Add the following to your AI tool's MCP configuration. | reuse |
| `settings.mcp.connect.token.server-url` | Server URL | reuse |
| `settings.mcp.connect.token.token` | Token | reuse |
| `settings.mcp.connected-tools.title` | Connected AI Tools | reuse |
| `settings.mcp.connection-sheet.action.connect` | Connect | reuse |
| `settings.mcp.connection-sheet.action.install-extension` | Install Extension | reuse |
| `settings.mcp.connection-sheet.done` | Done | reuse |
| `settings.mcp.connection-sheet.title` | Connect %@ | reuse |
| `settings.mcp.copy` | Copy | reuse |
| `settings.mcp.disconnect.action.disconnect` | Disconnect… | reuse |
| `settings.mcp.disconnect.confirm.action` | Disconnect | reuse |
| `settings.mcp.disconnect.confirm.message` | %@ will no longer be able to access Paste. | reuse |
| `settings.mcp.disconnect.confirm.title` | Disconnect “%@”? | reuse |
| `settings.mcp.enable.subtitle` | Allow AI apps to connect to Paste. Only apps you approve can access your clipboard items and pinboards. | reuse |
| `settings.mcp.enable.title` | Enable MCP | reuse |
| `settings.mcp.port.change` | Change | reuse |
| `settings.mcp.port.change-failed` | Couldn't change the port | reuse |
| `settings.mcp.port.title` | MCP Server Port | reuse |
| `settings.mcp.port.warning` | Changing the port disconnects and removes all connected AI tools. | reuse |
| `settings.mcp.tool.custom` | Custom Tool | reuse |
| `settings.mcp.tool.options` | Client options | reuse |
| `settings.mcp.tools.empty` | Nothing connected yet | reuse |
| `settings.mcp.tools.last-used` | Last used %@ | reuse |
| `settings.mcp.tools.never-used` | Never used | reuse |

### Intelligent Clipboard (Suggestions tab in the strip)

| Key | English (verbatim) | Super Paste |
|---|---|---|
| `intelligence.suggestions.action.allow-screen-access` | Allow Screen Access | reuse |
| `intelligence.suggestions.empty` | No suggestions | reuse |
| `intelligence.suggestions.screen-recording.subtitle` | Intelligent Clipboard reads the window you’re pasting into, only when you open Paste. An on-device model does the rest, and everything stays on your Mac. | reuse |
| `intelligence.suggestions.screen-recording.title` | Get suggestions for what you’re about to paste | reuse |
| `intelligence.suggestions.title` | Suggestions | reuse |
| `intelligence.suggestions.turn-off.text` | You can turn it back on any time in Paste Settings, under Intelligence. | reuse |
| `intelligence.suggestions.turn-off.title` | Turn off Intelligent Clipboard? | reuse |

### Search & filters

| Key | English (verbatim) | Super Paste |
|---|---|---|
| `empty-state.history` | History is empty | reuse |
| `empty-state.pinboard` | Pinboard is empty | reuse |
| `empty-state.search` | Nothing found | reuse |
| `search.filters.section.app` | App | reuse |
| `search.filters.section.date` | Date | reuse |
| `search.filters.section.device` | Device | reuse |
| `search.filters.section.pinboard` | Pinboard | reuse |
| `search.filters.section.type` | Type | reuse |
| `search.filters.title` | Filters | reuse |

### Item types (card headers, filters)

| Key | English (verbatim) | Super Paste |
|---|---|---|
| `item-type.color` | Color | reuse |
| `item-type.file-count` | plural: one = “File”; other = “%d files” | reuse |
| `item-type.image` | Image | reuse |
| `item-type.link` | Link | reuse |
| `item-type.multiple-files` | Multiple files | reuse |
| `item-type.text` | Text | reuse |
| `item-type.unknown` | Unknown | reuse |

### Item preview / editor

| Key | English (verbatim) | Super Paste |
|---|---|---|
| `edit-item.title.color` | Edit Color | reuse |
| `edit-item.title.image` | Edit Image | reuse |
| `edit-item.title.item` | Edit Item | reuse |
| `edit-item.title.link` | Edit Link | reuse |
| `edit-item.title.text` | Edit Text | reuse |
| `edit-item.toolbar.discard-changes` | Discard changes | reuse |
| `edit-item.toolbar.image.remove-background` | Remove Background | reuse |
| `edit-item.toolbar.image.restore-background` | Restore Background | reuse |
| `edit-item.toolbar.image.rotate-left` | Rotate Left | reuse |
| `edit-item.toolbar.image.rotate-right` | Rotate Right | reuse |
| `edit-item.toolbar.save-changes` | Save changes | reuse |
| `edit-item.toolbar.text.bold` | Bold | reuse |
| `edit-item.toolbar.text.italic` | Italic | reuse |
| `edit-item.toolbar.text.strikethrough` | Strikethrough | reuse |
| `edit-item.toolbar.text.underline` | Underline | reuse |
| `edit-item.toolbar.text.writing-tools` | Writing Tools | reuse |
| `editor.character-count` | plural: one = “%d character”; other = “%d characters” | reuse |
| `editor.character-label` | plural: one = “character”; other = “characters” | reuse |
| `editor.line-count` | plural: one = “%d line”; other = “%d lines” | reuse |
| `editor.line-label` | plural: one = “line”; other = “lines” | reuse |
| `editor.word-count` | plural: one = “%d word”; other = “%d words” | reuse |
| `editor.word-label` | plural: one = “word”; other = “words” | reuse |
| `preview.reveal-in-finder.title` | Reveal in Finder | reuse |
| `preview.unavailable.subtitle` | Preview can’t be shown, but the content is saved, and you’re able to paste it | reuse |
| `preview.unavailable.title` | Preview unavailable | reuse |

### New Text Item window

| Key | English (verbatim) | Super Paste |
|---|---|---|
| `create-item.action.create` | Create | reuse |
| `create-item.action.create-text-item` | Create text item | reuse |

### Pinboard create / edit

| Key | English (verbatim) | Super Paste |
|---|---|---|
| `pinboard.edit.title` | Edit Pinboard | reuse |
| `pinboard.new.title` | New Pinboard | reuse |
| `pinboard.people-count` | plural: one = “%d person contributes”; other = “%d people collaborate” | drop |

### Alerts & confirmations

| Key | English (verbatim) | Super Paste |
|---|---|---|
| `alert.cloudkit-unavailable.text` | Please check your iCloud settings to ensure you’re signed in and iCloud is enabled. | drop |
| `alert.cloudkit-unavailable.title` | iCloud Unavailable | drop |
| `alert.delete-pinboard.text` | The Pinboard and all its content will be deleted. This action cannot be undone. | reuse |
| `alert.delete-pinboard.title` | Delete “%@”? | reuse |
| `alert.delete-selected-items.title` | plural: one = “Delete %d item?”; other = “Delete %d items?” | reuse |
| `alert.delete-shared-item.text` | If you delete this item, other people will no longer have access to it and it will be deleted from all their devices. | drop |
| `alert.delete-shared-item.title` | Delete this shared item? | drop |
| `alert.delete-shared-items.text` | If you delete these items, other people will no longer have access to them and they will be deleted from all their devices. | drop |
| `alert.delete-shared-items.title` | plural: one = “Delete %d shared item?”; other = “Delete %d shared items?” | drop |
| `alert.delete-shared-pinboard.owner.text` | If you delete this pinboard, other people will no longer have access to it and it will be deleted from all their devices. | drop |
| `alert.delete-shared-pinboard.text` | It will be deleted from all your devices. To rejoin this shared pinboard, click the link you were invited with. | drop |
| `alert.delete-shared-pinboard.title` | Delete the shared “%@”? | drop |
| `alert.erase-history.text` | Pinned items and Pinboards won't be deleted. This action cannot be undone. | reuse |
| `alert.erase-history.title` | Are you sure you want to erase your Clipboard History? | reuse |
| `alert.pin-from-shared-list.text` | If you pin the selected items to %@, it will be duplicated to your pinboard. | drop |
| `alert.pin-from-shared-list.title` | Pin to %@? | drop |
| `alert.pin-to-shared-list.editor.text` | If you pin the selected items to %@, it will be duplicated and people added to that shared pinboard will be able to access it. | drop |
| `alert.pin-to-shared-list.editor.title` | Pin to %@? | drop |
| `alert.pin-to-shared-list.viewer.title` | You don't have access to pin items to %@ | drop |
| `alert.reduce-history-limit.text` | Pinned items and Pinboards won't be deleted. This action cannot be undone. | reuse |
| `alert.reduce-history-limit.title` | You have items older than the new history limit. Do you want to delete these older items and apply the new limit? | reuse |
| `alert.reset-local-data.action.reset` | Reset Local Data | reuse |
| `alert.reset-local-data.text` | Paste will move the damaged data to a “backup” folder next to it and start over. If you had iCloud sync on, your items and pinboards download again from iCloud. | reuse |
| `alert.reset-local-data.title` | Paste Can’t Open Its Data | reuse |
| `alert.share-unavailable.text` | Pinboard is still syncing to iCloud. Please try again in a moment. | drop |
| `alert.share-unavailable.title` | Sync in progress. | drop |
| `alert.store-unavailable.text` | iOS didn’t give Paste access to its data. Restart your device, then open Paste again. | iOS-only |
| `alert.store-unavailable.title` | Clipboard History Unavailable | iOS-only |
| `alert.sync-disabled.text` | Please enable iCloud sync in Settings and try again. | drop |
| `alert.sync-disabled.title` | iCloud Sync Disabled | drop |

### Diagnostics (Help menu)

| Key | English (verbatim) | Super Paste |
|---|---|---|
| `diagnostics.action.stop-and-copy-logs` | Stop and Copy Logs | reuse |
| `diagnostics.start.message` | Paste will restart to begin collecting diagnostic logs. You can stop diagnostics at any time from the menu. | reuse |
| `diagnostics.start.title` | Start Diagnostics | reuse |
| `diagnostics.stop.message` | Diagnostic logs will be copied so you can send them to support. | reuse |
| `diagnostics.stop.title` | Stop Diagnostics | reuse |

### In-app notifications (sidecar cards)

| Key | English (verbatim) | Super Paste |
|---|---|---|
| `notifications.discover-shared-pinboards.action.primary` | Learn More | drop |
| `notifications.discover-shared-pinboards.description` | Collaborate and stay in sync on your content. | drop |
| `notifications.discover-shared-pinboards.title` | Shared Pinboards | drop |
| `notifications.enable-direct-paste.action.primary` | Enable | reuse |
| `notifications.enable-direct-paste.description` | Paste items directly to any app. | reuse |
| `notifications.enable-direct-paste.title` | Enable Direct Paste | reuse |
| `notifications.enable-keyboard.description` | Get your copied content ready to paste wherever you type. | iOS-only |
| `notifications.enable-keyboard.title` | Enable Paste Keyboard | iOS-only |
| `notifications.enable-sync.action.primary` | Enable | drop |
| `notifications.enable-sync.description` | Securely sync your data on all devices. | drop |
| `notifications.enable-sync.title` | Enable iCloud Sync | drop |
| `notifications.intelligent-clipboard.description` | See how Paste suggests what you’ll paste next. | reuse |
| `notifications.intelligent-clipboard.title` | Meet Intelligent Clipboard | reuse |
| `notifications.liquid-glass.description` | Read about what’s new in Paste. | drop |
| `notifications.liquid-glass.title` | Paste in Liquid Glass | drop |
| `notifications.open-at-login.action.primary` | Enable | reuse |
| `notifications.open-at-login.description` | Automatically launch Paste when you restart your Mac. | reuse |
| `notifications.open-at-login.title` | Open at Login | reuse |
| `notifications.rate-app.action.primary` | Write a Review | drop |
| `notifications.rate-app.description` | Show your support and help others discover it. | drop |
| `notifications.rate-app.title` | Enjoying Paste? | drop |
| `notifications.run-in-background.action.primary` | Enable | reuse |
| `notifications.run-in-background.description` | Ensure Paste is always running. | reuse |
| `notifications.run-in-background.title` | Run in Background | reuse |
| `notifications.start-free-trial.action.primary` | Start | drop |
| `notifications.start-free-trial.description` | Try Paste on all your devices. | drop |
| `notifications.start-free-trial.title` | Start Your Free Trial | drop |
| `notifications.trial.active.description` | Keep Paste on all your devices after your free days end. | drop |
| `notifications.trial.active.title` | plural: one = “%d Day Left”; other = “%d Days Left” | drop |
| `notifications.trial.expired.description` | Buy now to keep Paste on all your devices. | drop |
| `notifications.trial.expired.title` | Your Trial Has Ended | drop |
| `notifications.try-on-mac.description` | Access everything you copy on all your devices. | iOS-only |
| `notifications.try-on-mac.title` | Try Paste on Mac | iOS-only |

### What's New

| Key | English (verbatim) | Super Paste |
|---|---|---|
| `whats-new.action.learn-more` | Learn More | reuse |
| `whats-new.action.rate-app-store` | Rate on App Store | reuse |
| `whats-new.action.see-it-in-action` | See it in action | reuse |
| `whats-new.description` | Paste now suggests the item you’ll most likely paste next, based on what you’re working on. | reuse |
| `whats-new.paste-5.action.learn-more` | Learn More | drop |
| `whats-new.paste-5.migration.failure.subtitle` | We couldn’t migrate your data due to an unknown issue. Your old data is safely backed up. Unfortunately, it can’t be used in Paste, so you’ll be starting fresh. | drop |
| `whats-new.paste-5.migration.failure.title` | Migration Failed | drop |
| `whats-new.paste-5.migration.progress` | Migrating your data, please wait… | drop |
| `whats-new.paste-5.migration.success.title` | Migration Completed! | drop |
| `whats-new.paste-5.migration.update-all-devices` | Update Paste on all your devices so everything stays in sync. | drop |
| `whats-new.paste-5.migration.warning.subtitle` | We have migrated most of your data, but there are %@ missing items. | drop |
| `whats-new.paste-5.migration.warning.title` | Migration Completed, But… | drop |
| `whats-new.paste-5.welcome.subtitle` | Faster, more reliable, and built for collaboration. | drop |
| `whats-new.paste-5.welcome.title` | Welcome to the New Paste | drop |
| `whats-new.paste-5.welcome.title-ios` | Welcome\nto the New Paste | iOS-only |
| `whats-new.title` | Intelligent Clipboard | reuse |

### Move to Applications prompt (direct-download build)

| Key | English (verbatim) | Super Paste |
|---|---|---|
| `move-to-applications.failure.title` | Could not move to Applications folder | reuse |
| `move-to-applications.prompt.action.cancel` | Do Not Move | reuse |
| `move-to-applications.prompt.action.move` | Move to Applications Folder | reuse |
| `move-to-applications.prompt.text.base` | I can move myself to the Applications folder if you'd like. | reuse |
| `move-to-applications.prompt.text.downloads-hint` | This will keep your Downloads folder uncluttered. | reuse |
| `move-to-applications.prompt.text.requires-password` | Note that this will require an administrator password. | reuse |
| `move-to-applications.prompt.title.system` | Move to Applications folder? | reuse |
| `move-to-applications.prompt.title.user` | Move to Applications folder in your Home folder? | reuse |

### Updates

| Key | English (verbatim) | Super Paste |
|---|---|---|
| `update.action.check-for-updates` | Check for Updates | reuse |

### Shared labels: actions (context menus, buttons)

| Key | English (verbatim) | Super Paste |
|---|---|---|
| `general.action.add` | Add | reuse |
| `general.action.cancel` | Cancel | reuse |
| `general.action.choose` | Choose | reuse |
| `general.action.continue` | Continue | reuse |
| `general.action.copy` | Copy | reuse |
| `general.action.copy-as-plain-text` | Copy as Plain Text | reuse |
| `general.action.create-pinboard` | Create Pinboard | reuse |
| `general.action.delete` | Delete | reuse |
| `general.action.deselect-all` | Deselect All | reuse |
| `general.action.done` | Done | reuse |
| `general.action.duplicate` | Duplicate | reuse |
| `general.action.edit` | Edit | reuse |
| `general.action.enable-sync` | Enable iCloud Sync | reuse |
| `general.action.erase` | Erase | reuse |
| `general.action.erase-history` | Erase History | reuse |
| `general.action.learn-more` | Learn more | reuse |
| `general.action.manage` | Manage | reuse |
| `general.action.manage-shared-pinboard` | Manage Shared Pinboard | drop |
| `general.action.manage-subscriptions` | Manage | drop |
| `general.action.ok` | OK | reuse |
| `general.action.open` | Open | reuse |
| `general.action.open-in` | Open in %@ | reuse |
| `general.action.open-with` | Open with %@ | reuse |
| `general.action.paste-as-plain-text` | Paste as Plain Text | reuse |
| `general.action.paste-to` | Paste to %@ | reuse |
| `general.action.pause` | Pause | reuse |
| `general.action.pause-for` | Pause for %@ | reuse |
| `general.action.pause-paste` | Pause Paste | reuse |
| `general.action.pin` | Pin | reuse |
| `general.action.preview` | Preview | reuse |
| `general.action.remove` | Remove | reuse |
| `general.action.rename` | Rename | reuse |
| `general.action.reset` | Reset | reuse |
| `general.action.restart-paste` | Restart Paste | reuse |
| `general.action.restore` | Restore | reuse |
| `general.action.resume` | Resume | reuse |
| `general.action.retry` | Retry | reuse |
| `general.action.reveal-in-finder` | Reveal in Finder | reuse |
| `general.action.save` | Save | reuse |
| `general.action.scan-document` | Scan Document | reuse |
| `general.action.select` | Select | reuse |
| `general.action.select-all` | Select All | reuse |
| `general.action.share` | Share | reuse |
| `general.action.share-pinboard` | Share Pinboard | drop |
| `general.action.show-in` | Show in %@ | reuse |
| `general.action.turn-off` | Turn Off | reuse |
| `general.action.unpin` | Unpin | reuse |

### Shared labels: menus, status, misc

| Key | English (verbatim) | Super Paste |
|---|---|---|
| `general.about-paste` | About Paste | reuse |
| `general.browser` | Browser | reuse |
| `general.clipboard` | Clipboard | reuse |
| `general.clipboard-history` | Clipboard History | reuse |
| `general.contact-support` | Contact Support | reuse |
| `general.copied` | Copied | reuse |
| `general.current-app` | current app | reuse |
| `general.do-not-ask-again` | Do not ask again | reuse |
| `general.enable-direct-paste` | Enable Direct Paste {icon:chevron.right} | reuse |
| `general.enabled` | Enabled | reuse |
| `general.error` | Error | reuse |
| `general.feature-request` | Feature Request | reuse |
| `general.get-started` | Get started | reuse |
| `general.getting-started` | Getting Started | reuse |
| `general.help` | Help | reuse |
| `general.help-center` | Help Center | reuse |
| `general.item-count` | plural: one = “%d item”; other = “%d items” | reuse |
| `general.keyboard-shortcuts` | Keyboard Shortcuts | reuse |
| `general.less` | Less | reuse |
| `general.more` | More | reuse |
| `general.name` | Name | reuse |
| `general.new-text-item` | New Text Item | reuse |
| `general.none` | None | reuse |
| `general.paste-on-twitter` | Paste on Twitter | drop |
| `general.paste-paused` | Paste Paused | reuse |
| `general.paste-resumed` | Paste Resumed | reuse |
| `general.paused` | Paused | reuse |
| `general.paused-until` | Paused until %@ | reuse |
| `general.pin-to` | Pin to | reuse |
| `general.pinboards` | Pinboards | reuse |
| `general.privacy-policy` | Privacy Policy | reuse |
| `general.privacy-policy.short` | Privacy | reuse |
| `general.product-updates` | Product Updates | reuse |
| `general.quit-paste` | Quit Paste | reuse |
| `general.search` | Search | reuse |
| `general.select-items` | Select Items | reuse |
| `general.selected-format` | %@ Selected | reuse |
| `general.settings` | Settings | reuse |
| `general.terms-of-use` | Terms of Use | reuse |
| `general.terms-of-use.short` | Terms | reuse |
| `general.unlimited` | Unlimited | reuse |
| `general.until` | Until %@ | reuse |
| `general.untitled` | Untitled | reuse |
| `general.useful-links` | Useful Links | reuse |
| `general.version-format` | Version %@ | reuse |
| `general.view` | View | reuse |

### Shared-pinboard collaboration (iCloud sharing)

| Key | English (verbatim) | Super Paste |
|---|---|---|
| `sidecar.collaboration-item.editor` | Editor | drop |
| `sidecar.collaboration-item.invited` | Invited | drop |
| `sidecar.collaboration-item.owner` | Owner | drop |
| `sidecar.collaboration-item.subtitle` | on this pinboard | drop |
| `sidecar.collaboration-item.viewer` | Viewer | drop |

### Licensing / paywall / review prompts

| Key | English (verbatim) | Super Paste |
|---|---|---|
| `feedback.leave-review.action.primary` | Leave review | drop |
| `feedback.leave-review.subtitle` | Why do you love Paste? How does it boost your productivity? What is your favorite use case? | drop |
| `feedback.leave-review.title` | We love you too! Would you mind to leave a review on the App Store? | drop |
| `licensing.activation-success.title` | Paste has been activated | drop |
| `licensing.license-activation.action.activate` | Activate | drop |
| `licensing.license-activation.action.activating` | Activating | drop |
| `licensing.license-activation.action.have-license-key` | I have a license key | drop |
| `licensing.license-activation.action.manage` | Manage License | drop |
| `licensing.license-activation.action.start-using-paste` | Start Using Paste | drop |
| `licensing.license-activation.activate-title` | Activate Your License | drop |
| `licensing.license-activation.key-hint` | Available on your order page or in your email | drop |
| `licensing.license-activation.key-placeholder` | Your License Key | drop |
| `licensing.license-activation.locked.subtitle` | Continue using Paste on all your devices. | drop |
| `licensing.license-activation.locked.title` | Keep Everything You Copied | drop |
| `licensing.license-activation.title` | Activate Paste | drop |
| `licensing.license-activation.trial.onboarding.title` | You're All Set | drop |
| `licensing.license-activation.trial.subtitle` | Your first 7 days are free. No card, no account. | drop |
| `licensing.license-activation.trial.title` | Try Paste on All Your Devices | drop |
| `licensing.paywall.action.pay-as-you-go` | %@, then %@ | drop |
| `licensing.paywall.action.restore-purchases` | Restore | drop |
| `licensing.paywall.action.view-all-plans` | View All Plans | drop |
| `licensing.paywall.all-plans.most-popular` | Most Popular | drop |
| `licensing.paywall.all-plans.paid-once` | paid once | drop |
| `licensing.paywall.all-plans.subtitle` | All plans include Paste on Mac and iOS devices. | drop |
| `licensing.paywall.all-plans.then-price` | then %@ | drop |
| `licensing.paywall.all-plans.title` | Choose Your Plan | drop |
| `licensing.paywall.comparative-price` | or %@ | drop |
| `licensing.paywall.connecting-to-app-store` | Connecting to App Store | drop |
| `licensing.paywall.error.load-subscriptions` | Error loading available subscriptions | drop |
| `licensing.paywall.error.network` | Error connecting to the App Store | drop |
| `licensing.paywall.error.network.recovery` | Please check your internet connection and try again. | drop |
| `licensing.paywall.error.no-products-available` | No subscription plans are available right now. Please try again in a moment. | drop |
| `licensing.paywall.error.no-purchases-found` | No purchases found | drop |
| `licensing.paywall.error.no-purchases-found.recovery` | Please make sure you're logged in with the same Apple ID you originally used to subscribe.\n\nAlso, check your App Store and iCloud account settings. | drop |
| `licensing.paywall.error.purchase` | Purchase not completed | drop |
| `licensing.paywall.error.purchase.recovery` | We couldn't complete your purchase. Please try again in a moment. If it keeps happening, write to us at support@pasteapp.io and we'll sort it out. | drop |
| `licensing.paywall.error.restore-purchases` | Error restoring purchases | drop |
| `licensing.paywall.error.restore-purchases.recovery` | %@\n\nPlease check your App Store and iCloud account settings. | drop |
| `licensing.paywall.features.icloud-sync` | Fast and secure iCloud sync across all devices | drop |
| `licensing.paywall.features.unlimited-clipboard` | Unlimited Clipboard History and Pinboards | drop |
| `licensing.paywall.features.updates` | Regular app updates and new features | drop |
| `licensing.paywall.offer.action.all-plans` | All Plans | drop |
| `licensing.paywall.offer.action.decline` | I Don't Like Subscriptions | drop |
| `licensing.paywall.offer.introductory.subtitle` | A one-time welcome offer to unlock Paste on all devices. | drop |
| `licensing.paywall.offer.introductory.text` | on your first year | drop |
| `licensing.paywall.offer.introductory.title` | Get %@%% Off Your First Year | drop |
| `licensing.paywall.offer.renewal.subtitle` | Keep unlimited clipboard history and all of Paste. | drop |
| `licensing.paywall.offer.renewal.text` | on your next year | drop |
| `licensing.paywall.offer.renewal.title` | Get %@%% Off When You Renew | drop |
| `licensing.paywall.promo.header` | Productivity Boost\nwith 30% Off | drop |
| `licensing.paywall.reviews.title` | People Everywhere Love Paste | drop |
| `licensing.paywall.single-choice.no-trial.title` | Start Today | drop |
| `licensing.paywall.single-choice.title` | Start Free | drop |
| `licensing.paywall.status.restoring` | Restoring purchases | drop |
| `licensing.paywall.subtitle` | Try Paste for free on your Mac and iOS devices. Pay only if you choose to continue, or cancel at any time. | drop |
| `licensing.paywall.testimonials.title` | The Pros Love It Too | drop |
| `licensing.paywall.title` | Start Your Free Trial | drop |
| `licensing.paywall.trial.step1.description` | Paste has been installed and is ready to use. | drop |
| `licensing.paywall.trial.step1.title` | Install Paste | drop |
| `licensing.paywall.trial.step2.description` | Start using Paste on all your devices. | drop |
| `licensing.paywall.trial.step2.title` | Get Full Access | drop |
| `licensing.paywall.trial.step3.description` | Get notified about when your trial will end. | drop |
| `licensing.paywall.trial.step3.title` | Trial Reminder | drop |
| `licensing.paywall.trial.step4.description` | You’ll be charged unless you cancel anytime before. | drop |
| `licensing.paywall.trial.step4.title` | Trial Ends | drop |
| `licensing.paywall.trial.title` | How the Trial Works | drop |
| `licensing.subscription.action.buy-now` | Buy Now | drop |
| `licensing.subscription.action.claim-offer` | Claim Offer | drop |
| `licensing.subscription.action.start-free-trial` | Start Free Trial | drop |
| `licensing.subscription.action.start-your-free-trial` | Start Your Free Trial | drop |
| `licensing.subscription.action.subscribe` | Subscribe | drop |
| `licensing.subscription.action.try-it-free` | Try It Free | drop |
| `licensing.subscription.introductory-offer.free-trial` | %@ free | drop |
| `licensing.subscription.introductory-offer.pay-as-you-go` | %@ for the first %@ | drop |
| `licensing.subscription.lifetime.action.switch-to-lifetime` | I Don't Like Subscriptions | drop |
| `licensing.subscription.lifetime.feature-1` | All features on all devices | drop |
| `licensing.subscription.lifetime.feature-2` | Free future updates | drop |
| `licensing.subscription.lifetime.feature-3` | Support development | drop |
| `licensing.subscription.lifetime.subtitle` | Subscription helps us continuously improve Paste. But if you’d rather pay once, you can. | drop |
| `licensing.subscription.lifetime.title` | Paste Lifetime.\nOne payment, yours forever. | drop |
| `licensing.subscription.promotional-description.annual` | Best value | drop |
| `licensing.subscription.promotional-description.family` | For everyone at home | drop |
| `licensing.subscription.promotional-description.lifetime` | No subscription | drop |
| `licensing.subscription.promotional-description.monthly` | Pay as you go | drop |
| `licensing.trial-started.title` | Your trial has started | drop |

### Settings: subscription & iOS-only settings

| Key | English (verbatim) | Super Paste |
|---|---|---|
| `settings.action-extension.title` | Action Extension | iOS-only |
| `settings.collect-clipboard-contents.title` | Collect Clipboard contents | iOS-only |
| `settings.collect-clipboard-contents.when-app-becomes-active` | When App Becomes Active | iOS-only |
| `settings.collect-clipboard-contents.when-keyboard-becomes-active` | When Keyboard Becomes Active | iOS-only |
| `settings.keyboard.title` | Keyboard | iOS-only |
| `settings.made-with-love.title` | Made with {icon:heart} by Paste Team | reuse |
| `settings.paste-for-mac.title` | Try Paste on Mac | iOS-only |
| `settings.pasteboard-access.title` | Allow Paste from Other Apps | iOS-only |
| `settings.siri-and-shortcuts.title` | Siri & Shortcuts | iOS-only |
| `settings.subscription.header` | One Subscription,\nEndless Productivity | drop |
| `settings.subscription.not-subscribed.subtitle` | You're not subscribed yet. | drop |
| `settings.subscription.title` | Subscription | drop |
| `settings.widget.title` | Widget | iOS-only |

### Other iOS-only strings

| Key | English (verbatim) | Super Paste |
|---|---|---|
| `extension.migration.action.open-paste` | Open Paste to continue | iOS-only |
| `item-preview.tap-to-rename` | Tap to rename | iOS-only |
| `keyboard-extension.content-copied` | Copied. Now paste anywhere | iOS-only |
| `keyboard-extension.tutorial.step-enable-keyboard` | Tap Enable Paste Keyboard | iOS-only |
| `keyboard-extension.tutorial.step-go-to-keyboard` | Go to Keyboard | iOS-only |
| `keyboard-extension.tutorial.step-open-paste` | Open Paste | iOS-only |
| `keyboard-extension.tutorial.step-open-settings` | Tap ⋯ and open Settings | iOS-only |
| `keyboard-extension.tutorial.title` | Paste Keyboard needs Full Access | iOS-only |
| `onboarding.home-screen-widget.action.primary` | Enable Paste Widget | iOS-only |
| `onboarding.home-screen-widget.action.secondary` | Enable Later in Settings | iOS-only |
| `onboarding.home-screen-widget.bottom-sheet.action.primary` | Go to Home Screen | iOS-only |
| `onboarding.home-screen-widget.bottom-sheet.step1` | Hold your Home Screen to launch an edit mode and tap “Edit” | iOS-only |
| `onboarding.home-screen-widget.bottom-sheet.step2` | Tap “Add Widget” | iOS-only |
| `onboarding.home-screen-widget.bottom-sheet.step3` | Find Paste app in the list | iOS-only |
| `onboarding.home-screen-widget.bottom-sheet.step4` | Choose a template you like | iOS-only |
| `onboarding.home-screen-widget.bottom-sheet.title` | How to Enable Paste\nWidget? | iOS-only |
| `onboarding.home-screen-widget.subtitle` | Assign shortcuts and access Paste from your Home Screen with a single tap. | iOS-only |
| `onboarding.home-screen-widget.title` | Speed Up with Widget | iOS-only |
| `onboarding.introduction.subtitle` | Paste is a time machine for your Clipboard that lets you instantly find anything you’ve ever copied and use it whenever you need it again. | iOS-only |
| `onboarding.introduction.title` | A Better Way\nto Copy and Paste | iOS-only |
| `onboarding.keyboard-extension.action.primary` | Enable Paste Keyboard | iOS-only |
| `onboarding.keyboard-extension.action.secondary` | Enable Later in Settings | iOS-only |
| `onboarding.keyboard-extension.allow-full-access-bottom-sheet.action.primary` | Open Settings | iOS-only |
| `onboarding.keyboard-extension.allow-full-access-bottom-sheet.subtitle` | Paste needs Full Access to securely sync with your iCloud and support all content types. It never transmits any sensitive information to anyone, including the developer. | iOS-only |
| `onboarding.keyboard-extension.allow-full-access-bottom-sheet.title` | Allow Full Access | iOS-only |
| `onboarding.keyboard-extension.how-to-bottom-sheet.action.primary` | Open Settings | iOS-only |
| `onboarding.keyboard-extension.how-to-bottom-sheet.step1` | Open Settings and tap “Keyboards” | iOS-only |
| `onboarding.keyboard-extension.how-to-bottom-sheet.step2` | Turn on “Paste” | iOS-only |
| `onboarding.keyboard-extension.how-to-bottom-sheet.step3` | Turn on “Allow Full Access” | iOS-only |
| `onboarding.keyboard-extension.how-to-bottom-sheet.step4` | Confirm allowing to securely sync with your iCloud | iOS-only |
| `onboarding.keyboard-extension.how-to-bottom-sheet.title` | How to Enable Paste\nKeyboard? | iOS-only |
| `onboarding.keyboard-extension.keyboard-installed-bottom-sheet.subtitle` | While typing in any app, touch and hold {icon:globe} and select Paste to access it. | iOS-only |
| `onboarding.keyboard-extension.keyboard-installed-bottom-sheet.title` | Keyboard Installed | iOS-only |
| `onboarding.keyboard-extension.subtitle` | Get your copied content ready to paste wherever you type. | iOS-only |
| `onboarding.keyboard-extension.title` | Paste with Keyboard | iOS-only |
| `onboarding.pasteboard-access.action.primary` | Allow Paste from Other Apps | iOS-only |
| `onboarding.pasteboard-access.action.secondary` | Enable Later in Settings | iOS-only |
| `onboarding.pasteboard-access.bottom-sheet.action.primary` | Open Settings | iOS-only |
| `onboarding.pasteboard-access.bottom-sheet.step1` | Open Settings and tap “Paste from Other Apps” | iOS-only |
| `onboarding.pasteboard-access.bottom-sheet.step2` | Select “Allow” | iOS-only |
| `onboarding.pasteboard-access.bottom-sheet.title` | How to Allow Paste from Other Apps? | iOS-only |
| `onboarding.pasteboard-access.subtitle` | Allow Paste to save content from your Clipboard automatically so you don't get distracted every time it needs access. | iOS-only |
| `onboarding.pasteboard-access.title` | Save Automatically | iOS-only |
| `onboarding.save-extension.action.primary` | Enable Action Extension | iOS-only |
| `onboarding.save-extension.action.secondary` | Enable Later in Settings | iOS-only |
| `onboarding.save-extension.bottom-sheet.action.primary` | Open Share Menu | iOS-only |
| `onboarding.save-extension.bottom-sheet.step1` | Open Share Menu and tap “More” | iOS-only |
| `onboarding.save-extension.bottom-sheet.step2` | Scroll down and tap “Edit Actions” | iOS-only |
| `onboarding.save-extension.bottom-sheet.step3` | Add “Copy to Clipboard History” from Other Actions | iOS-only |
| `onboarding.save-extension.bottom-sheet.step4` | Move it to Favorites | iOS-only |
| `onboarding.save-extension.bottom-sheet.title` | How to Enable Action\nExtension? | iOS-only |
| `onboarding.save-extension.subtitle` | Save links, text, images, and any other content using the {icon:square.and.arrow.up} share menu. | iOS-only |
| `onboarding.save-extension.title` | Copy from Any App | iOS-only |
| `onboarding.sync.action.secondary.off` | {icon:icloud.slash} Enable iCloud Sync | iOS-only |
| `onboarding.sync.action.secondary.on` | {icon:checkmark.icloud} Secured with iCloud Sync | iOS-only |
| `onboarding.sync.bottom-sheet.subtitle` | Keep data in sync across all devices. | iOS-only |
| `onboarding.sync.bottom-sheet.title` | iCloud Sync | iOS-only |
| `onboarding.sync.bottom-sheet.toggle-title` | Enable iCloud Sync | iOS-only |
| `onboarding.sync.subtitle` | Keep and organize everything you copy across your iPhone, iPad, and Mac. | iOS-only |
| `onboarding.sync.title` | Access on Any Device | iOS-only |


---

## Hard-coded strings (not in Localizable.strings)

### Paste Stack window [R storyboard]

| Where | String |
|---|---|
| Window title label | Paste Stack |
| Empty placeholder | Empty |
| Close button | (icon `NSStopProgressFreestandingTemplate`, no text) |
| Stack-direction toggle | (icons `icon.sort-up` / `icon.sort-down`, no text) |

### Hidden main menu (gives standard key equivalents to the panel and settings windows) [B]

| Menu | Items (key equivalent) |
|---|---|
| (app) | Quit Paste (⌘Q), from `general.quit-paste` |
| File | Close (⌘W) |
| Edit | Undo (⌘Z) [U: the label was not recovered; the key equivalent was], Redo (⇧⌘Z), Cut (⌘X), Copy (⌘C), Paste (⌘V), Select All (⌘A) |
| Window | Minimize (⌘M) |

### Strip tooltips and composed labels [B]

| Where | String |
|---|---|
| Filters button tooltip | `Filters` + ` (` + `⌘F` + `)` → "Filters (⌘F)" |
| Pinboard tab tooltip | `<name>` + ` (` + `<prev shortcut>` + `, ` + `<next shortcut>` + ` to navigate)` |
| Shortcuts pane, Quick Paste row suffix | `+ 1...9` |
| Search date-filter suggestions | `Today`, `Last 30 days`; ranges are rendered `<from> to <to>` |
| Colour card footer format toggle | `RGB` (the other format is the hex code, printed with `#%06X`) |
| Diagnostics header (copied logs) | `--- Diagnostic Info ---`, `App: `, `OS: macOS `, `-----------------------` |

### App Intents / Shortcuts actions [R Metadata.appintents + B]

| Element | String |
|---|---|
| Action title | Create Item |
| Description | Create a new item in the specified list using the content passed as input. |
| Summary | Create item with ${content} in ${list} |
| Params | Content (Text), List (List: "Clipboard or Pinboard") |
| Action title | Create Pinboard |
| Description | Create a pinboard with the name provided as input. |
| Summary | Create pinboard ${name} |
| Params | Name (Text) |
| Action title | Get Item at Index |
| Description | Retrieve an item from a specified position in a list. |
| Summary | Get Item at ${index} from ${list} |
| Params | Index ("Item Index"), List |
| Action title | Get Latest Item |
| Description | Retrieve the latest item of a specified type from a list. |
| Summary | Get latest ${type} item from ${list} |
| Params | Type ("Text or Link"; enum *Item Type*: Text, Link), List |
| Entity type name | List |
| Errors | List not found · Content is empty · Can't create item · Name must not be empty · Index out of bounds |
| Siri / Spotlight phrases (Create Item) | Create ${applicationName} item · Save ${applicationName} item · Add ${applicationName} item · Create text item with ${applicationName} · New text item in ${applicationName} · Save to ${applicationName} · Add to ${applicationName} |
| App Shortcut short title | Create Item (symbol `square.and.pencil`) |
| List entity images | `clock.arrow.circlepath` (Clipboard), `circlebadge.2.fill` (pinboard, tinted with its colour) |

### MCP server (`PasteMCP`) [B]

Server identity and instructions:

| Element | String |
|---|---|
| Server instructions | Paste is a clipboard manager for macOS. Use these tools to search and read clipboard history, save new items, and manage Pinboards on the user's behalf. |
| `.mcpb` manifest description | Search your clipboard history, save new items, and manage Pinboards on this Mac. |
| Server version | 1.0.0 |

Tools (title, then description, verbatim):

| Tool | Title | Description |
|---|---|---|
| `search` | Search saved items | Search the user's saved items — clipboard history and pinboards both — with optional filters. With no arguments, returns the most recent items. `query` is free text matched against titles and content. Filters (combinable): `type` (see allowed values); `app` / `device` — match the `app` / `device` field shown on returned items; `pinboard_id` — a pinboard id from `list_pinboards`; `title` — a title substring; `date_from` / `date_to` — ISO-8601 bounds for a half-open timestamp range (either may be omitted for an open end). Returns flat summaries (id, type, preview, timestamp, app, device); `timestamp` is when the item entered clipboard history (ISO-8601), absent for pinned-only items; call read_item for full content. Results are ordered newest first. A search resolves at most 100 matches, the 100 most recent — narrow the query rather than raising `limit` to reach older items. |
| `read_item` | (title not recovered) | Read the full content of a saved item by id (returned by search). Text comes back verbatim, cut at `<N>` characters if it is longer (structured output then carries `truncated` and `totalLength`); links return their URL; colors return a `#RRGGBB` hex string; files return their paths one per line; images return the image itself (downscaled and re-encoded) for vision-capable clients. |
| `create_item` | Create clipboard item | Create an item from text `content`. Without `list_id` it is added to clipboard history, where it shows up in search. With `list_id` (a private, non-shared pinboard) it is pinned to that pinboard: if the same content is already in history the existing item is pinned (and stays in history), otherwise a new pinned-only item is created that is not added to history. Shared pinboards are not supported. Does not write to the system clipboard. The item's type is auto-detected from the content — usually `text`, but content that reads as a 6-digit hex color (e.g. "#FF0000") becomes a `color` and a URL becomes a `link`. Returns the created item summary (id, type, preview, timestamp, app, device); `timestamp` is absent when the item is pinned to a pinboard only (not in history). |
| `update_item` | Update saved item | Update a saved item's `title`, its `content`, or both (at least one is required). Passing `title` sets the item's title; an empty string clears it. Passing `content` replaces the body and re-runs type auto-detection (text/color/link), exactly like create_item. Content edits are rejected for image and file items (their title can still be changed). Returns the updated item summary. |
| `delete_item` | Delete saved item | Delete a saved item entirely and irreversibly — from clipboard history and the pinboard it's pinned to, removing the underlying record for good. Destructive, two-step: call without `confirm` to preview, then with `confirm: true` to delete. To only unpin an item while keeping it, use remove_item_from_pinboard. |
| `list_pinboards` | (title not recovered) | List the user's pinboards. Returns flat summaries (id, name, itemCount). Use the returned id with add_item_to_pinboard / remove_item_from_pinboard / rename_pinboard. |
| `create_pinboard` | (title not recovered) | Create a new pinboard with the given name. Returns the created pinboard summary (id, name, itemCount). |
| `rename_pinboard` | (title not recovered) | Rename an existing pinboard. Returns the updated pinboard summary. |
| `delete_pinboard` | (title not recovered) | Delete a pinboard. Destructive, two-step: call without `confirm` to preview (nothing changes), then with `confirm: true` to delete. Pinned items stay in clipboard history. |
| `add_item_to_pinboard` | Add item to pinboard | Pin a clipboard history item to a pinboard. Idempotent — adding the same item twice keeps it pinned once. Returns the updated pinboard summary. |
| `remove_item_from_pinboard` | Remove item from pinboard | Unpin an item from a pinboard. The item stays in clipboard history if it was there; only the pinning is removed. Returns the updated pinboard summary. |

Parameter descriptions:

| Param | Description |
|---|---|
| search `query` | Free text matched against item titles and content. |
| search `type` | Item type filter. |
| search `app` | Source application filter — matches the `app` field shown on returned items. |
| search `device` | Device filter — matches the `device` field shown on returned items. |
| search `title` | Title substring filter. |
| search `pinboard_id` | Restrict to items pinned to this pinboard (id from list_pinboards). |
| search `date_from` | ISO-8601 start (inclusive) of the timestamp range, e.g. 2026-05-01T00:00:00Z. A date-only value (e.g. 2026-05-01) starts at the beginning of that day. |
| search `date_to` | ISO-8601 end of the timestamp range. A full date-time is exclusive; a date-only value (e.g. 2026-05-01) covers that whole day. |
| search `limit` | Maximum number of items to return. Defaults to 20, capped at 100. |
| read_item `id` | Identifier of the item (from search results). |
| create_item `content` | Text content for the new item. Stored verbatim. |
| create_item `list_id` | Optional id of a private (non-shared) pinboard from list_pinboards. When set, the item is pinned to that pinboard instead of going to history; content already in history is pinned rather than duplicated. |
| update_item `id` | Identifier of the item to update (from search results). |
| update_item `title` | New title. Pass an empty string to clear the title. |
| update_item `content` | New text content. Replaces the body and re-detects the type. |
| delete_item `id` | Identifier of the item to delete (from search results). |
| delete_item / delete_pinboard `confirm` | Must be true to actually delete. Omit or false to preview only. |
| create_pinboard `name` | Display name for the new pinboard (whitespace-trimmed). |
| rename_pinboard `id` | Identifier of the pinboard to rename (from list_pinboards). |
| rename_pinboard `name` | New display name (whitespace-trimmed). |
| delete_pinboard `id` | Identifier of the pinboard to delete (from list_pinboards). |
| add_item_to_pinboard `item_id` | Identifier of the clipboard item (from search results). |
| add_item_to_pinboard `pinboard_id` | Identifier of the destination pinboard (from list_pinboards). |
| remove_item_from_pinboard `item_id` | Identifier of the clipboard item to unpin. |
| remove_item_from_pinboard `pinboard_id` | Identifier of the pinboard to unpin the item from. |

Tool messages and errors:

| String |
|---|
| Preview — would delete this item from history and its pinboard, for good. Call again with confirm: true to delete. |
| Deleted item. |
| Preview — would delete pinboard "`<name>`" (`<n>` items). Call again with confirm: true to delete. Items that are also in the clipboard history stay there; items that live only in this pinboard are deleted with it. |
| Deleted pinboard "`<name>`". |
| Invalid arguments: `<detail>` |
| No clipboard item found with id `<id>`. Use search to find valid item ids. |
| No pinboard found with id `<id>`. Use list_pinboards to see valid ids. |
| Pinboard `<id>` is a shared pinboard, which create_item doesn't support. Use a private pinboard. |
| `content` cannot be empty. |
| `name` cannot be empty. |
| Pass at least one of `title` or `content` to update. |
| Cannot edit the content of an image or file item. You can still change its title. |
| `date_from` must be before `date_to`. |
| `` `<param>` must be an ISO-8601 date or date-time: `<value>` `` |
| Unknown tool: `<name>` |

OAuth consent page (HTML served by the local MCP server):

| Element | String |
|---|---|
| `<title>` / `<h1>` | Connect `<client name>` |
| Summary | `<client name>` wants to use Paste on this Mac. |
| Permissions title | This will allow access to: |
| Permission 1 | View and manage your clipboard items |
| Permission 2 | View and manage your pinboards |
| Note | You can revoke this connection later in Paste Settings. |
| Buttons | Cancel · Connect |

Client connection snippets (shown in the Connect sheet):

| Client | Snippet / action |
|---|---|
| desktop assistant app | builds `paste.mcpb` (manifest + `paste-icon.png`, launches `Contents/MacOS/paste-mcp-stdio`) and opens it |
| command-line assistant | `client mcp add --transport http --scope user paste <url>` |
| Codex | `codex mcp add paste --url <url>` (TOML form: `[mcp_servers.paste]\nurl = "<url>"`) |
| Cursor | deeplink `cursor://anysphere.cursor-deeplink/mcp/install?name=Paste&config=<base64 {"url":…}>` |
| VS Code | deeplink `vscode:mcp/install?<json {"name":"Paste","type":"http","url":…}>` |
| Windsurf | edits `~/.codeium/windsurf/mcp_config.json` with `{"mcpServers": {"paste": {"url": "<url>"}}}` |
| Custom | shows Server URL + Token to paste into any MCP config |

### Info.plist [R]

| Key | String |
|---|---|
| `NSScreenCaptureUsageDescription` | Paste looks at the window you are pasting into to suggest the right clip. The picture is used on this Mac only and never stored. |
| `MDItemKeywords` | copy,paste,snippets,clipboard,history,productivity |

### Dropped third-party UI strings

The Setapp framework ships its own localized error strings (e.g. "This copy of %{app_name} requires an active Setapp account installed on your Mac."). PostHog and Sentry show no UI. None of these are carried over.
