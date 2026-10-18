# Parity review: Super Paste against Paste 7 on macOS

How Super Paste's screens compare with the reference app, element by element, and what changed to close each gap.
The reference is the product imagery Paste publishes (its website and Mac App Store screenshots, which show the
macOS 26 look) read next to `ui-reference.md` (numbers from the binary) and `behaviour.md`. Super Paste's side comes
from its offscreen renders (`STRIPKIT_RENDER_DIR` / `SUPERPASTE_RENDER_DIR` with `swift run SuperPasteSelfTest`).
Nothing was launched and no screen was captured.

Reference images (kept out of the repository): App Store `mac_-_screen_1…8.png`, the website's `hero-cover.png`,
`cards.png`, `cover.png`, `card-1…4-media.png`. "Spec" cites `ui-reference.md` sections.

Where the imagery and the spec disagree, the imagery wins; where the imagery is silent, the spec stands.

## What the first launch looks like

| Element | Paste (reference) | Super Paste before | Fix |
|---|---|---|---|
| Onboarding pages | Introduction → Quick Start (behaviour §8); permissions on demand | Five pages: the two, then Accessibility, privacy notes, a shortcut recap | Two pages. The extra pages, their views, illustrations and strings are gone |
| After Continue | The strip comes up with a pinboard of welcome items (spec §12, strings `onboarding.content.*`) | The window closed; nothing else happened. With history empty, the next thing the user saw was "History is empty", if they found the strip at all | Continue closes the window, seeds a Welcome pinboard once (four notes, three links with drawn preview art, all pinned-only) and slides the strip up on it |
| ⇧⌘V taken by another app | Paste's own log: "Carbon hot key is already held by another caller" | Logged only; the shortcut silently did nothing (the reference app running alongside takes ⇧⌘V and ⇧⌘C) | One-time alert "⇧⌘V is used by another app" with Open Shortcuts Settings; warning row under the recorder and a red sidebar badge in Settings › Shortcuts; registration retried every 30 s and 1.5 s after onboarding |
| Quick Start recorder | 120 wide (spec §12) | 150 | 120 in onboarding, 150 in Settings |

## The strip

| Element | Paste (reference + spec) | Super Paste before | Fix |
|---|---|---|---|
| Panel | Glass slab inset 8, radius 26, full width at the bottom, toolbar 60, cards 8 below it, 24 at the sides and bottom (hero-cover; spec §2.4–2.6) | Same geometry | none needed |
| Older macOS panel | Flat `windowBackgroundColor` bar, radius 0, cards radius 10 (spec §2.4, §4.1) | Same | none needed |
| Toolbar, idle | Magnifier alone, then Clipboard chip (selected: ink10 capsule, clock icon) and pinboard chips with 12 pt dots, "+", "…" at the far right (hero-cover, sync screenshot) | Same | none needed |
| Toolbar, searching | Field centred, ≥ 400 and ≥ 25 % wide, accent focus ring hugging the capsule; the tabs stay, collapsed to icon-only squares after the field (card-2-media; spec §3.1, §3.4) | Tabs and "+" faded out entirely; the text view's rectangular focus ring was off | Tabs collapse to 28 pt squares (label alpha 0) after the field, "+" folds under them; the standard focus ring masked to the field's capsule |
| Card body | White (`textBackgroundColor`), radius 16, continuous; shadow black 0.08, blur 2 | Same | none needed |
| Selection ring | 4 pt accent band outside the body, radius 20 | Same | none needed |
| Header band | App colour (pinboard colour when pinned), title3 medium white, date callout white 0.8, the app icon as tall as the band bleeding off the right edge, clipped by the card corner (hero-cover zoom; spec §4.2–4.3) | Same | none needed |
| Header of items created in a pinboard | Title alone, vertically centred, no date (App Store "Design Assets" cards: Brand Color, Button Variants…) | Date under the title (creation date) | Items without `copiedAt` show the title alone |
| Text card | 13 pt body, 12 pt side insets, rich text keeps its own background (Notes' yellow); "N characters" centred over a fade (hero-cover; spec §4.5) | Same | none needed |
| Compact text card footer | Footer over a fade, no opaque strip (spec §4.5) | Text showed through the top of the footer | The fade turns solid sooner |
| Link card | Preview image filling the top, title body semibold, host callout secondary (hero-cover) | Same | none needed |
| Image card | Picture fills the body; "W × H" pill at the bottom centre, dark frosted with light text whatever the picture (screens 2, 4, 6) | Light frosted pill with dark text | The pill always draws in the dark appearance with ink85 text |
| Colour card | Body is the colour; the code centred in a fixed-pitch font, secondary ink on the colour ("#FFCB78", screen 7) | Proportional callout, primary ink | Fixed-pitch callout size, ink50, appearance from the colour's brightness |
| File card | Icon or Quick Look thumbnail over one head-truncated path including the name, "Documents/website/backup.zip" (screens 3, 6) | File name on one line, folder on another | One label: the full path (folder for several files), "~/" dropped |
| Unknown card | `exclamationmark.triangle` 32 pt, callout label (spec §4.5); the card says "Preview unavailable" (behaviour §2.5) | The raw pasteboard type ("com.example.custom") | "Preview unavailable" |
| Quick-paste badge | 18 pt pill, bottom right, number in secondary, shown while ⌘ is held | Same | none needed |
| Sidecar cards | Icon, title3 semibold, callout medium text, capsule button, close (spec §5) | Same | none needed |
| Empty states | 26 pt ink26, "History is empty" / "Pinboard is empty" / "Nothing found" | Same | none needed |
| Context menu | Open / Reveal / Show in …; Paste to %@, Paste as Plain Text, Copy; Edit, Rename, Delete; Pin ▸ with colour dots and Create Pinboard; Preview, Share ▸ (spec §4.8; screen 4 shows the same groups) | Same | none needed. Screen 4 says "Quick Look" and adds Writing Tools; the installed 7.0.3 strings say "Preview", kept |
| Show/hide | Slide up 0.15 s (0.2, 0.8, 0.2, 1), down 0.20 s ease-in-out; closed-state reset after 10 s | Same | none needed |
| Scrolling, drag, hover | Horizontal only, no hover state, 0.45 s press before a drag, 4 pt reorder marker | Same | none needed |

## Preview, Paste Stack, menus, Settings

| Element | Paste (reference + spec) | Super Paste before | Fix |
|---|---|---|---|
| Preview header | 38 pt: `xmark.circle.fill` at +10, headline title, Edit / Pin / Share (spec §6.2); screen 5 shows the close button and capsule buttons | Same | none needed |
| Files preview footer | "Documents/website/backup.zip · 12.4 MB" and Reveal in Finder (screen 5) | Size only | Path (head-truncated) · size |
| Text preview footer | "N characters · N words · N lines" monospaced digits, ink50 | Same | none needed |
| Colour preview | Swatch, HEX / RGB / HSL rows | Same | none needed |
| Paste Stack panel | 322 wide, title bold 13, close at left, direction toggle at right, 44 pt rows with type icons (spec §9) | Same | none needed |
| Menu bar icon | Paste's own "P" logo; plays 17 frames at 1/48 s on every capture (logo fades, a tilted card drops in, the glyph scales back); paused badge | Super Paste's card glyph, static; dimmed while paused | The glyph animates the same way on every capture (its own drawing; the icon itself stays Super Paste's) |
| App menu | About / — / New Text Item ⌘N, Settings… ⌘, / — / Help ▸ / — / Pause ▸ / — / Quit ⌘Q (spec §10) | Open Super Paste, Paste Stack, New Text Item / Pause / Settings…, Getting Started, About / Quit | The reference order. Help ▸ holds Getting Started, Keyboard Shortcuts, Help Center, Feature Request, Contact Support |
| Settings window | 200 pt sidebar + 440 pt pane, 52 pt pane title, group boxes radius 12 at ink85 0.03 (spec §11) | Same | none needed. The panes differ by design: Sync, Integrations and About replace Intelligence and Subscription |
| Settings › Shortcuts | Four recorders, Quick Paste and Plain Text modifiers, reset | Same, but nothing about a shortcut that doesn't work | Warning row under the recorder and the sidebar badge while another app holds it |

## Still different, and why

- **Icon and name.** Super Paste keeps its own icon, menu bar glyph and name, as agreed.
- **Liquid Glass.** Offscreen renders use a stand-in for `NSGlassEffectView`; on a running macOS 26 the real glass
  draws. The reference imagery's warm tint comes from its wallpaper.
- **Context menu wording.** The App Store image says "Quick Look" and has a Writing Tools item; the installed 7.0.3
  binary's strings say "Preview" and keep Writing Tools inside the editor. Super Paste follows the binary.
- **Audio cards.** The imagery shows an "Audio" type (artwork and track title). Paste 7.0.3's item types are text,
  link, image, colour, files and unknown (behaviour §2.5); audio files are file cards here.
- **Intelligent Clipboard.** The Picks button, Suggestions tab and the Metal glow need Apple Intelligence and were
  dropped by design (behaviour §22.2).
- **Welcome pinboard contents.** The reference's seeded links point at Paste's help site and X account and use its
  own artwork; Super Paste's point at its website and GitHub, with artwork drawn in code.
- **Dark mode.** No dark reference imagery exists; dark values follow `ui-reference.md` §1.1.
