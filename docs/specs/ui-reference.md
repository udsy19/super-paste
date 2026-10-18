# Paste 7.0.3 — UI Reference for Super Paste

Static UI reference for Paste 7.0.3 (Setapp build `com.wiheads.paste-setapp`, CFBundleVersion 29869049, LSMinimumSystemVersion 14.0, LSUIElement). It was taken from the installed app without running it: the arm64 slice of the binary, its Objective‑C and Swift metadata, the asset catalogs, the localization tables, the PasteStack storyboard, and `default.metallib`. The app was never launched and the screen was never captured.

## Evidence tags

| Tag | Meaning |
|---|---|
| **[B 0x…]** | Read from the arm64 binary. The address is a function or instruction. `fn_X` means the function starting at X. |
| **[R]** | Read from a resource: `Assets.car`, a bundle, a storyboard nib, an `.aiff`, or the metallib. |
| **[S]** | String from `PastePackages_PasteLocalization.bundle/en.lproj/Localizable.strings(dict)`, or a binary literal. |
| **[U]** | Inferred, or not proven by a single instruction. Treat it as a guess and check it. |

## Version branches

Almost every visual value has two branches, chosen at runtime with `_stdlib_isOSVersionAtLeast(26,0,0)`:

- **"26"** — macOS 26 (Liquid Glass).
- **"older"** — macOS 14 and 15.

Both values are given wherever they differ. Super Paste targets macOS 14+, so it needs both.

## Architecture notes (for porting)

- **UI technology by area:**
  - The strip, the cards and the top bar are **AppKit** (layer‑backed custom `NSView`s in the `PasteUI` and `PasteCoreUI` modules).
  - Settings, onboarding, What's New, the permission screens, the filter browser and the toast content are **SwiftUI** hosted in AppKit.
- **Module names:** Paste, PasteUI, PasteCoreUI, PasteCore, PasteSearch, PasteShortcut, PasteOnboarding, PasteWhatsNew, PasteSystemPermissions, PasteRouting, PastePicks (on‑device "Intelligent Clipboard"), and PasteMCP (MCP server). Taken from the Swift metadata.
- **Size classes:** a `SizeClass` enum drives most strip metrics: `large`, `regular`, `small`, `compact` [B fieldmd `PasteUI.SizeClass`].

---

## 1. Global design tokens

### 1.1 Colour palette (PasteUI `NSColor` statics)

- **Light/dark selection.** Each dynamic colour is built with `colorWithName:dynamicProvider:`. The provider returns the dark value when `bestMatchFromAppearancesWithNames:` matches one of `[DarkAqua, VibrantDark, AccessibilityHighContrastDarkAqua, AccessibilityHighContrastVibrantDark]` [B fn_100227ae8].
- **Order.** In every table below, the first value is light and the second is dark. This is confirmed by the gray pair, which equals Apple's systemGray light/dark.
- **Token names.** The names in the first column are ours. The binary is stripped and keeps no names.

**Text and fill tokens**

| Token (our name) | Light | Dark | Main uses | Evidence |
|---|---|---|---|---|
| `ink85` (primary) | black @ 0.85 | white @ 0.85 | Toolbar icon tint (26), search text, compact header title, preview close button | [B init 0x100220334, getter fn_10021f9d8] |
| `ink50` (secondary) | black @ 0.50 | white @ 0.55 | Footers (char count, W×H, file size), older toolbar tint, social icons | [B 0x1002204b0, fn_10021fa18] |
| `ink26` | black @ 0.26 | white @ 0.26 | Colour-picker selected ring, sidecar close button, item footer | [B 0x100220624, fn_10022078c] |
| `ink10` | black @ 0.10 | white @ 0.10 | Search field bg, selected tab/button bg, pressed (forced alpha 0.15), editor border | [B 0x1002207e8, fn_10022094c] |
| `ink05` | black @ 0.05 | white @ 0.05 | Hover bg for tabs/buttons, sidecar button bg, titled-button border | [B 0x1002209a8, fn_10021fa58] |
| `ink02` | black @ 0.02 | white @ 0.02 | Onboarding setup card | [B 0x100220b28, fn_100220c90] |

**Solid and surface colours**

| Token (our name) | Light | Dark | Main uses | Evidence |
|---|---|---|---|---|
| `white` / `black` | #FFFFFF | #000000 | Header text on coloured card headers; shadow colour | [B 0x10021fa98 / 0x10021fb34] |
| `gray` | #8E8E93 (0.557, 0.557, 0.576) | #98989D (0.596, 0.596, 0.616) | Gray pinboard, unknown-app header | [B 0x10021fbd0] |
| `yellow` | #F2B600 (0.949, 0.714, 0) | same | Yellow pinboard (both themes) | [B 0x10022005c] |
| system green / blue / red / orange / yellow / purple / pink | `NSColor.system*` | — | Pinboard colours (26) | [B 0x10021fda0…0x1002202a8] |
| `surface1` | #F2F2F7 | #1C1C1E | Surface / background | [B 0x10023877c] |
| `surface2` | #FFFFFF | #2C2C2E | Surface / background | [B 0x100238938] |
| `surface3` | #F2F2F7 | #2C2C2E | Surface / background | [B 0x100238c70] |
| `linkBg` | #FFFFFF | #141414 (0.078) | Link card and link preview background | [B 0x100238f14] |
| `windowBgDyn` | white | `windowBackgroundColor` | LinkItemCell / LinkItemContentView | [B 0x10023860c] |
| `fill` | #767680 @ 0.12 | #767680 @ 0.24 | Fill (systemFill‑like) | [B 0x100238ad8] |
| `accent` | `controlAccentColor` | — | Selection ring, primary buttons, selected filter items | [B 0x1002384e8] |

System colours used directly include `labelColor`, `secondaryLabelColor`, `tertiaryLabelColor`, `separatorColor`, `textBackgroundColor` (card body) and `windowBackgroundColor`.

### 1.2 Typography

Paste uses **macOS text styles** almost everywhere, through helpers that call `+[NSFont preferredFontForTextStyle:options:]` [B fn_1002212bc]:

| Helper | Text style | Point size on macOS [U standard values] | Evidence |
|---|---|---|---|
| title2 | `NSFontTextStyleTitle2` | 17 | [B 0x10022125c] |
| title3 | `NSFontTextStyleTitle3` | 15 | [B 0x100221268] |
| headline | `NSFontTextStyleHeadline` | 13 bold | [B 0x100221274] |
| subheadline | `NSFontTextStyleSubheadline` | 11 | [B 0x100221280] |
| body | `NSFontTextStyleBody` | 13 | [B 0x10022128c] |
| callout | `NSFontTextStyleCallout` | 12 | [B 0x100221298] |
| footnote | `NSFontTextStyleFootnote` | 10 | [B 0x1002212a4] |
| caption1 | `NSFontTextStyleCaption1` | 10 | [B 0x1002212b0] |

- **Weight modifiers** call `systemFont(ofSize: font.pointSize, weight:)`:
  - `.bold` [B 0x100221364]
  - `.semibold` [B 0x100221370]
  - `.medium` [B 0x10022137c]
- **Explicit sizes:**
  - Intelligent Clipboard placeholder: 15 semibold title, 13 regular body [B 0x10001aab4/ab7c].
  - Empty-state label: 26 regular [B 0x100019e5c].
  - Toast symbol: 86 [B 0x10025294c].
  - Onboarding title/body: 22 bold / 13 [B 0x100a1b580/b940].
  - Permission icons: 64 [B 0x100a032fc].
  - Colour-editor value: `userFixedPitchFontOfSize: 22` [B 0x100274df4].
  - What's New code sample: `userFixedPitchFontOfSize: 18` [B 0x1002615e4].
  - Counters: `monospacedDigitSystemFont`.

### 1.3 SF Symbols

PasteUI keeps one `SFSymbol` enum whose cases return these names [B 0x10022c098–0x10022d3d8]:

```
add.badge app.badge app.dashed apple.writing.tools arrow.clockwise arrow.triangle.2.circlepath
arrow.forward arrow.up arrow.up.forward arrow.up.forward.square arrow.uturn.backward at bell.fill
bold calendar checkmark checkmark.circle checkmark.circle.fill checkmark.icloud checkmark.seal
chevron.backward chevron.down chevron.down.circle chevron.forward chevron.right chevron.up
chevron.up.chevron.down chevron.up.circle circle circlebadge circlebadge.2 circle.fill
circle.rectangle.filled.pattern.diagonalline clock.arrow.circlepath circle.dashed delete.backward
delete.backward.fill doc doc.on.clipboard doc.on.doc doc.on.doc.fill doc.plaintext doc.viewfinder
ellipsis exclamationmark.circle.fill exclamationmark.triangle exclamationmark.triangle.fill eye
eye.fill finder flag flag.checkered flag.fill gear gear.badge gearshape gift globe hammer.circle
hand.raised heart heart.fill infinity info.circle ipad iphone italic keyboard
keyboard.chevron.compact.down ladybug laptopcomputer lifepreserver lightbulb
line.3.horizontal.decrease link lock lock.fill macbook macbook.and.iphone magnifyingglass minus
paintpalette paperplane party.popper pause pause.circle play.circle pencil
pencil.and.ellipsis.rectangle person.2.fill person.crop.circle.badge.checkmark phone photo pin plus
power questionmark questionmark.circle questionmark.app rectangle.and.pencil.and.ellipsis return
rotate.left rotate.right safari shift shift.fill sparkles square.2.stack.3d square.and.arrow.up
square.and.arrow.up.fill square.and.pencil star.fill strikethrough text.alignleft
text.justify.leading trash underline waveform waveform.path.ecg xmark xmark.app xmark.circle
xmark.circle.fill puzzlepiece.extension
```

- Numbered symbols are built as `"<n>.circle"` / `"<n>.circle.fill"`, for example the Pause‑for menu's `15.circle`, `30.circle`, `1.circle`, `3.circle` and `8.circle`.
- The fallback image is `questionmark.square` [B 0x10022d45c].
- Also used: `NSStopProgressFreestandingTemplate` (Paste Stack close) [R].

### 1.4 Shared metric tokens

`PasteUI.Geometry.{Spacing, CornerRadius, IconSize}` are caseless enums of statics. Their getters return 20, 6, 12, 14, 16, 18, 22 and 160 [B 0x100229294–0x1002292d0], but the names of the individual values were stripped [U]. Every concrete value in this document was read at its use site instead.

**Corner-radius summary**

| Element | 26 | Older |
|---|---|---|
| Panel | 26 | 0 |
| Card body | 16 | 10 |
| Card selection ring | 20 | 14 |
| Search field / tab chip / toolbar button | capsule (height/2) | 6 (large buttons), 5 (regular buttons) |
| Sidecar card | 16 | 10 |

Other radii:
- Toast: 20
- Suggestions menu: 10
- Group box: 12
- Preview content border: 5
- Permission illustrations: 10
- What's New image: 20

---

## 2. The main panel ("strip")

### 2.1 Window
- **Class:** `Paste.MainWindow`, a subclass of **NSPanel** [B dispatch].
- **Created in** `MainWindowController.init` [B 0x10001b740–0x10001b88c] with:
  - `styleMask = 136` (0x88 = `.resizable | .nonactivatingPanel`, borderless); backing buffered; `defer: YES` [B 0x10001b7e4].
  - `level = 24` (`NSMainMenuWindowLevel`, above the Dock) [B 0x10001b810].
  - `isMovable = NO`, `hasShadow = NO`, `autorecalculatesKeyViewLoop = YES`; delegate is self [B 0x10001b804–0x10001b838].
  - `canBecomeKey` / `canBecomeMain` overridden [B 0x100088a14/a1c].
- **Height** (ivars) [B 0x10001b750–0x10001b784]:

| | Height |
|---|---|
| Default | **332 pt** |
| Minimum | **252 pt** |
| Maximum | **412 pt** |

- `-layoutIfNeeded` pins `minSize` and `maxSize` to the current frame, so only the custom resize handle can change the height [B 0x100088e40].
- **Frame persistence:** `setFrameUsingName:"PasteAppMainWindow_NSWindowFrameAutosaveName"`. If no frame is saved, the height is set to 332 [B fn_100088794].
- **Screen sharing:** `ScreensharingPrivacyManager` sets `sharingType` from the setting "Show During Screen Sharing" [B 0x10005b0a0/0x10005b3b4].

### 2.2 Position
- **On every show** the frame is: origin = `NSScreen.mainScreen.frame.origin`, width = `mainScreen.frame.width`, height = the content view's height [B fn_10001c088 0x10001c17c–0x10001c1f0].
- So the panel is **anchored to the bottom edge, full screen width**. It uses `frame`, not `visibleFrame`, so it **covers the Dock**.
- **26:** the visible glass slab is inset **8 pt** left, right and bottom inside that full-width window (§2.4).

### 2.3 Show / hide animation

| | Show [B fn_10001c088] | Hide [B fn_10001c82c → fn_10001caf0, 0x10001ca70] |
|---|---|---|
| Content view frame | Set to the window frame, then offset to `y = −height`; animated back to `y = 0` | Animator sets content view origin `y = −height` |
| Movement | Slides up its full height | Slides down its full height |
| Duration | **0.15 s** | **0.20 s** |
| Timing | `CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1.0)` [B 0x10001c370–0x10001c3e8] | `kCAMediaTimingFunctionEaseInEaseOut` [B fn_10023bfd4] |
| Mechanism | `NSAnimationContext.runAnimationGroup` [B fn_10023bbf0] | same |

Details:
- **Show:**
  - The superview gets `clipsToBounds = YES` during the slide.
  - The window background is `clearColor` during the animation.
  - On completion, on **older** systems only, the window background is set to `windowBackgroundColor` [B 0x10001c5fc–0x10001c634].
- **Hide:**
  - Posts the will‑close notification.
  - Resets the first responder.
  - The background goes back to clear (older) [B 0x10001c8dc].
- **About 10 s after closing**, a `SelfInvalidatingTimer` runs the "closed state" reset; this probably clears the search [B fn_1000aefec 0x1000af2a8] [U semantics].

### 2.4 Background and material
- **`BackgroundEffectView(cornerRadius:)`** [B fn_10023e61c]:
  - **26:** an `NSGlassEffectView` (Liquid Glass) whose `contentView` is a plain `NSView`, with `cornerRadius = 26` [B fn_100096d34, 0x10023e728–0x10023e74c].
  - **Older:** an opaque layer‑backed view filled with `windowBackgroundColor`, corner radius 0 (flat, edge‑to‑edge bar) [B 0x10023e684–0x10023e6e8].
  - No `NSVisualEffectView` blur is used for the strip on either branch.
- **Background insets inside MainView:**
  - **26:** top 0, left 8, bottom 8, right 8.
  - **Older:** 0 on all sides [B fn_100094e54 0x100094e90].
- **26 extra:** `IntelligenceGlowView`, an additive-composited Metal glow (§17), sits in MainView for the Intelligent Clipboard.

### 2.5 Layout inside the panel
- **Toolbar:** pinned to the top, **height 60** [B 0x100095128].
- **Collection view:**
  - top = toolbar bottom [B 0x1000951e0]
  - bottom = MainView bottom **−8 (26)** / **0 (older)** [B 0x100095244]
- **Resize handle** (`MainWindow.ResizeHandle`):
  - A **10 pt‑high** strip pinned to the top edge [B 0x1000896b8].
  - Cursor: private `_windowResizeNorthSouthCursor` (assembled from string pieces "_","window","Resize","North","South","Cursor"), falling back to `NSCursor.resizeUpDownCursor` [B fn_1000989d0, 0x1011dfe60].
  - Live drag clamps the height to **252…412** and re-anchors to the bottom [B 0x100089418–0x10008942c].
  - End of drag calls `setFrame(display:YES, animate:YES)` and saves the frame.
  - A **double‑click** (`clickCount == 2`) animates back to **332** [B 0x1000982ac, 0x1000894e8].
- **Keyboard:** MainView routes Tab / Shift‑Tab itself; other keys go to `interpretKeyEvents`, so typing starts a search [B fn_100096220].

### 2.6 Card grid geometry (horizontal strip)
- **Content insets** (`CollectionView.ContentLayoutConfiguration`): **top 8, left 24, bottom 24, right 24**; **inter‑item spacing 24** [B 0x100082ac0–0x100082adc].
- When the Sidecar is visible, left = sidecar width + 24 [B 0x10007ba30].
- **Cards are square.** Side = collection height − (top + bottom) = **collection height − 32** [B fn_1002483f4].
- **Size class** from the card side [B fn_10007b5c4, 0x10007b970]:

| Card side | Size class |
|---|---|
| ≥ 280 | `large` |
| 240 – < 280 | `regular` |
| 200 – < 240 | `small` |
| < 200 | `compact` |

- **Resulting card side by panel height** (derived):

| Panel height | 26 (collection = H − 68) | Older (collection = H − 60) |
|---|---|---|
| 332 (default) | 232 → small | 240 → regular |
| 252 (min) | 152 → compact | 160 → compact |
| 412 (max) | 312 → large | 320 → large |

- **Size-class change animation:** `SizeClassTransitionManager` with `Animator`; per‑metric linear interpolation between the old and new class [B fn_10026be20].

---

## 3. Top bar (toolbar, height 60)

### 3.1 Layout, left to right [B fn_100064f50]
1. **Picks button** (Intelligent Clipboard):
   - Leading +16, vertically centred [B 0x100065014].
   - Icon is a 20 pt Metal `PicksIconView` [B 0x100067500].
   - Appears with an opacity fade plus a "bounce" keyframe animation, keyTimes 0 / 0.45 / 1, **0.32 s** [B fn_10006566c] (scale values [U]).
2. **Notification bar** (pause / sync indicators):
   - Leading = picks trailing + 8, or toolbar + 16 when Picks is not offered [B 0x100064e2c/0x100064ef4].
   - Horizontal stack, spacing 8, inset 10 top and bottom; items 28×28 [B fn_1000b5c44, 0x100093458].
   - **Pause item:** large ToolbarButton, `pause.circle`; its menu pops at y −10 [B fn_1000b7504].
   - **Sync item:** `arrow.triangle.2.circlepath`, symbol scale large [B 0x100063df4].
3. **Search bar:** vertically centred, leading ≥ notification bar trailing + 8 [B 0x100065138].
4. **Tab bar** (History and pinboards):
   - leading = search trailing + 8
   - `centerX = toolbar.centerX` at priority 250, so it is roughly centred [B 0x1000651f0/0x100065264]
5. **"+" create‑pinboard button:**
   - `plus`, tooltip "Create Pinboard (⌘N)".
   - leading = tab bar trailing + 8 at priority 750.
   - trailing ≤ menu leading −8 (26) / −16 (older) [B 0x100065318/0x1000653ac].
6. **"…" menu button:** `ellipsis`, trailing −16 [B 0x100065458].

**Active search** [B fn_100066844]:
- The search bar centres on the toolbar.
- Width ≥ **400** and ≥ **25 %** of the toolbar width.
- "+" trailing snaps to the tab bar trailing.
- Animated with ease-out at the default duration [B 0x100066684].

### 3.2 ToolbarButton (PasteUI)
- **Sizes:**

| Size | Dimensions | Symbol config text style | Title font |
|---|---|---|---|
| `.large` (all toolbar icons) | **32×32** [B 0x100258e98] | title2 | title3 |
| `.regular` | height **22**, width ≥ 32, side padding 8, stack spacing 4 [B 0x100258f98–0x10025adc4] | body [B 0x10025784c] | body [B 0x100258cd4] |

- **Corner radius:** **26:** capsule (height/2). **Older:** **6** (large) / **5** (regular) [B 0x1002585a0–5c0].
- **Border:** 1 pt `ink05`, only when the button has a title.
- **Pull‑down arrow:** `chevron.down` 8×8 [B 0x100259168].
- **State backgrounds** [B fn_100259f9c]:
  - pressed: `ink10` at alpha 0.15
  - selected: `ink10`
  - hover: `ink05`
  - otherwise clear
- **Tint:**
  - normal: `ink85` (26) / `ink50` (older)
  - disabled: `secondaryLabelColor` with systemEffect 3
  - primary button: bg `controlAccentColor` with white text, both `withSystemEffect`

### 3.3 Search field
- **Shape:** background `ink10` [B 0x10004fc3c]; radius height/2 (26) / **6** (older), circular curve [B fn_100050b70]. The focus ring is drawn as a mask of the same shape [B fn_10004cd28].
- **Inside, left to right** [B fn_10004fcec]:
  - `magnifyingglass` icon at +8 (symbol config body on 26, title2 on older) [B 0x10004f710]
  - text input: height 20, leading icon + 4, text container inset (0, 2) [B fn_10004e3b8]
  - clear button 16×16 at text + 4 [B fn_10004bfa0]
  - filters button: borderless, `line.3.horizontal.decrease`, tooltip "Filters (⌘F)", trailing −8 [B fn_10004f84c]
- **Text:** placeholder **"Search"** [S `general.search`]; typing font body, colour `ink85` [B fn_10004dbec].
- **Filter tokens inside the query** (inline chips) [B fn_10004e6b0/fn_10004ec3c]:
  - padding 2 / 6 / 2 / 6
  - 12×12 icon, spacing 2
  - label body in `labelColor`
  - continuous capsule on `ink10`
  - Insert animation "filtersBounce": scale 1 → 1.16 → 0.98 → 1, keyTimes 0.35 / 0.7, **0.28 s** [B fn_10004f13c].
- **Filter browser** (popover from the filters button) [B 0x100048c34]:
  - SwiftUI, transient, not animated.
  - Sections **App / Date / Device / Pinboard / Type** [S], each titled in callout bold `secondaryLabelColor`.
  - `LazyVGrid`, flexible columns, spacing 8/10; sections 16 apart.
  - Items padded 10 × 6, body font. Selected = accent bg with white text; pressed = black @ 0.1.
  - "More / Less" toggle [B 0x10003bdf8–c088, fn_100035600].
- **Autocomplete suggestions menu:**
  - Separate window, `BackgroundEffectView` with radius 10 (glass on 26).
  - Placed above the field and clamped to `visibleFrame − 6` [B 0x1000544f8, 0x100073804].
  - Rows: padding 3 / 8 / 3 / 8, icon 18×18, spacing 7. Selected row = accent bg, white text, subtitle white @ 0.6 [B fn_100014b74, fn_100014ce4].
  - List inset 5.
  - Scroll indicators 18 pt with 12 pt chevrons [B fn_1000553c8].

### 3.4 Tab bar (History + pinboards)
- **Geometry:**
  - Inset 10 top and bottom [B fn_100029a00].
  - `TabBarScrollView` is 40 high with insets 6 / 7 / 6 / 7, so **chips are 28 high** [B 0x100033a40] [U derived].
  - Spacing between chips **8** [B 0x1000282cc].
- **Chip anatomy:** icon at +8, label at icon + 4, trailing −8, label max width **200**; label body, single line [B fn_100043c9c, fn_100030294].
- **Corner radius:** capsule (26) / **6** (older) [B fn_100043fc4].
- **Collapsed state:** a square icon-only chip; label alpha 0 [B fn_100043340].
- **States** [B fn_100045040]:
  - selected: `ink10`
  - hover: `ink05`
  - pressed: `ink10` @ 0.15
  - editing: `ink05`
  - drag‑destination: `ink10`
- **Icons:**
  - Pinboard: 16 pt box with a 12 pt colour glyph (custom drawn on a 256 canvas) [B fn_10001969c, 0x10027f2f0].
  - **History:** 18 pt box, `clock.arrow.circlepath` at 13 pt (26) / 15 pt (older), regular weight, `ink85` or `ink50` [B fn_10001980c].
- **Overflow:**
  - Horizontal scrolling with 1 pt edge shadows (gradient clear → `labelColor` @ 0.16 → clear) that appear after 7 pt of scroll [B fn_100033ec8/fn_100034a84].
  - Tooltip "<name> (<prev>, <next> to navigate)" [S 0x10002a198].
- **Rename:** inline editing with its own focus ring [B fn_100030624].
- **Tab context menu** [B fn_10000431c] (exact order and separators [U]):
  - Rename (`pencil`)
  - colour row
  - Manage Shared Pinboard (`person.crop.circle.badge.checkmark`)
  - Share Pinboard (`square.and.arrow.up`)
  - Erase History (`trash`, History tab only)
  - Delete / Remove (`trash`)
- **Colour row** [B fn_100004ff0–fn_10000604c]:
  - Horizontal, spacing 2, insets 2 / 10 / 2 / 10, height 26.
  - Cells 22×22 with a circular 1 pt ring around a 14 pt swatch (inset 4).
  - Selected: ring filled with `textBackgroundColor`, border `ink26`. Hover also shows the border.

### 3.5 Pinboard colours
`PinboardAttributes.Color`: red, orange, yellow, green, blue, purple, pink, gray [B fieldmd]. Resolved in [B fn_100271a2c]:

| Colour | 26 (system colours) | Older (stored hex code) |
|---|---|---|
| red | systemRed | **#F0554D** |
| orange | systemOrange | **#FA9214** |
| yellow | custom **#F2B600** | **#FAB700** |
| green | systemGreen | **#52CC64** |
| blue | systemBlue | **#62A9F5** |
| purple | systemPurple | **#B663E0** |
| pink | systemPink | **#FA506F** |
| gray | #8E8E93 / #98989D | **#8F8F93** |

---

## 4. Cards (items in the strip)

### 4.1 Card shell (`PasteCoreUI.BaseCell`) [B fn_1002848b8 / fn_100284198]
- **Card body** (`contentView`, a layer‑backed view):
  - Background **`textBackgroundColor`** (white in light, dark gray in dark).
  - Corner radius **16 (26) / 10 (older)**.
  - Corner curve **continuous (26) / circular (older)**.
- **Selection ring** (`selectionView`):
  - Sits **4 pt outside** the body on all sides (insets −4) [B fn_1002843fc].
  - Radius **20 (26) / 14 (older)**, which is body radius + 4.
  - So the ring reads as a 4 pt band.
  - Colour [B fn_100283dfc]:
    - selected: **`controlAccentColor`**
    - selected **and dimmed**: accent converted to **grayscale** (`genericGrayColorSpace`) [B fn_1002382c8]
    - otherwise none
- **Card shadow** (`NSShadow`) [B fn_100283eb0]:

| | 26 | Older |
|---|---|---|
| Colour | black @ **0.08** | black @ **0.10** |
| Offset | (0, 0) | (0, −1) |
| Blur | 2 | 2 |

### 4.2 Card header (`ItemCell.HeaderView`) — per size class
- **`ItemCell.Layout`** (content top offset, header height, lock‑icon Y offset) [B fn_10026bf04]:

| Size class | Header height | Content top | Lock Y |
|---|---|---|---|
| large | **56** | 56 | −10 |
| regular | **52** | 52 | −10 |
| small | **48** | 48 | −10 |
| compact | **36 (26) / 34 (older)** | = header height; **0** when "compact content full‑size" | −10; **8 (26) / 7 (older)** when full‑size |

  Transitions between classes interpolate these values linearly [B fn_10026be20].
- **`HeaderView.Layout`** [B fn_100268bb8]:

| Field | large / regular / small | compact |
|---|---|---|
| Title font | **title3 + medium** (15 medium) | **headline + semibold** (13 semibold) |
| Title colour | white | gradient style: white @ 0.85; transparent style: `ink85` |
| Date font | **callout** (12) | **body** (13) |
| Date colour | white @ **0.8** | gradient: white @ 0.55; transparent: `ink50` |
| Labels stack | vertical, leading‑aligned, spacing **−1** | horizontal, centre‑Y, spacing 0 |
| Labels X offset | **−70 / −66 / −62** when the app icon shows, otherwise −12 | −30 |
| App icon height | **84 / 80 / 76** [B tables 0x100dbb7d8/0x100dbb7f0] | 20 |
| App icon X offset | +14, so the icon overhangs and is clipped at the right edge | −8 |
| App icon alpha | 1 (0 when hidden) | 0.9 |
| Pinboard icon X offset | 8 | −12 |
| Colour band alpha (`pinboardColorAlpha`) | 1 | 0 (no coloured band in compact) |
| Gradient alpha | 0 | 1 (gradient style) / 0 (transparent) |

- **Construction** [B fn_100267a58, fn_100267dfc]:
  - Header subviews: background view (colour fill), content view, pinboard icon (`NSImageView`), app icon (`NSImageView`, scaling 3 = proportionally up‑or‑down), title label, date label.
  - A **gradient view**: black @ 0.4 → clear, 64 pt high, pinned to the top.
  - Header and content views clip.
- **Look:**
  - Coloured top band, with title and relative time in white.
  - A large source‑app icon bleeding off the right edge of the band.
  - White card body below.
  - The bundled What's New illustration shows the same look [R `whats-new.png`].

### 4.3 Header colour, date, lock
- **Header band colour** [B 0x1002718a8, 0x1002cb2b8]:
  - If the item is in a pinboard, the pinboard colour (§3.5).
  - Otherwise the source app's stored colour (`ApplicationEntity.rawColor`, packed `0xAARRGGBB`; an alpha byte of 0 means opaque).
  - If neither exists, the dynamic `gray`.
  - App colours #62A9F5 and #F0554D are remapped to systemBlue and systemRed [B 0x100271b54].
- **How the app colour is derived from the icon** [B 0x100391750, 0x100390f78]:
  1. Render the icon at 128 px.
  2. Keep only fully opaque pixels with saturation > 0.25.
  3. Take the **most frequent** colour.
  4. Cap saturation at **0.85**.
  5. If brightness > 0.4, clamp brightness to **0.75–0.96**.
  - Fallback is `NSColor.grayColor`.
- **App icon:**
  - Sized to the app-icon height (84 / 80 / 76 / 20).
  - Missing icons use the asset `icon.unknown-app` [B 0x10026870c].
  - When the item is in a pinboard, the app icon is hidden and a **12 pt pinboard list icon** shows instead [B 0x1002686d4, 0x100268b84].
- **Labels:** inset 12 from leading, vertically centred on the app icon [B 0x10026818c].
- **Title text:** the item type label [S `item-type.*`: Text, Link, Image, Color, Multiple files / "%d files", Unknown], or the user's custom title (inline-editable `HeaderView.TitleLabel`) [U exact rule].
- **Date label** [B 0x1002651e4, 0x1002cc1c8]:
  - Non‑compact: `RelativeDateTimeFormatter`, named style (e.g. "2 hours ago").
  - Compact: `DateComponentsFormatter`, abbreviated, 1 unit (e.g. "2h").
  - Tooltip: absolute date (medium date, short time).
  - Refreshes every **30 s**.
- **Lock overlay** (licence locked; not shown on onboarding items) [B 0x1002698c4, 0x1002de3bc]:
  - 56×56 circle (radius 28) on the frosted backdrop.
  - `lock` symbol 28 pt, secondary colour at 60 %.
- **Frosted backdrop** (`ItemCell.BackdropView`, used by the badge, size pill and lock): `NSVisualEffectView`, material **.menu (5)**, within-window blending, always active [B 0x1002650c0].

### 4.4 Quick‑paste badges (⌘1–9) and plain‑text indicator
- **Pill:**
  - **18 pt tall, radius 9**, 6 pt horizontal padding, internal spacing 4.
  - Sits **8 pt** from the body's trailing and bottom edges [B 0x10026a63c, 0x10026a368, 0x10026c43c].
- **Number:** callout (12 pt) in the secondary colour (`ink50`).
- **Plain‑text indicator:** `text.alignleft` at footnote size, tinted secondary at 65 % [B 0x10026a160, 0x100269ed0].
- **Numbering:** the first nine visible items get 1–9 [B 0x10007c1ac].
- **Visibility:** a `flagsChanged` monitor drives it [B 0x100269fd8, 0x10026a47c]:
  - Quick‑paste modifiers held: the number shows.
  - Plain‑text modifiers held: the indicator shows.
  - Otherwise the badge is hidden.
  - The modifiers are configurable in Settings → Shortcuts ("Quick Paste … + 1...9", "Plain Text mode").

### 4.5 Card bodies by content type
- **Text** [B 0x10026fadc, 0x10026f3a0, 0x10026f694, 0x10026fca4, 0x1002706f8]:
  - Preview: first **20 000** characters, unlimited lines (clipped by the card), natural alignment, primary colour, **13 pt (body)**.
  - Insets: left / right **12**, top **10**, bottom ≤ 10.
  - Background: the rich text's dominant background colour if it has one, otherwise `linkBg` (white / #141414). Appearance follows that colour's brightness [B 0x100221bb4].
  - **Footer:** "N characters" [S `editor.character-count`], callout, secondary, centred, 10 pt from the bottom. It sits over a **32 pt fade** plus an **18 pt opaque strip** (0 in compact).
- **Link** [B 0x10026e2dc–0x10026e5ec, 0x10026dca4, 0x10026ed08]:
  - Preview area: og:image under a fade.
  - Favicon **42×42**, radius **12 (26, continuous) / 10 (older)**; fallback symbol `safari` at 42 pt.
  - Footer stack (vertical, leading, spacing 3):
    - title: body semibold (13), primary, word-wrap, truncating the last line
    - URL: callout, secondary, char-wrap
  - Link previews are off when "Generate Link Previews" is off.
- **Image** [B 0x1002645bc, 0x100264a5c, 0x100264190]:
  - Checkerboard background (`CheckerboardView`) with an aspect‑scaling image view.
  - **Size pill** "%d × %d" (pixels): backdrop, radius 9, 18 tall, 6 padding, callout, secondary. Horizontally centred on the same baseline row as the quick‑paste badge.
- **Colour** [B 0x100261aa0, 0x100227754, 0x100262874]:
  - The whole body is filled with the colour.
  - Label: "#RRGGBB" uppercase (device RGB), callout, centred, up to 2 lines, primary.
  - Appearance (light/dark text) follows the colour's brightness.
- **Files** [B 0x100262f9c, 0x100262fd0, 0x1002639a0, 0x100262b00]:
  - File icon or thumbnail (256×256 source).
  - Title: the file name, or "Multiple files" / "%d files" [S].
  - Path label truncated at the head (`HeadTruncatedLabel`, split on "/"); insets 10 / 12 / −2.
- **Unknown:** `exclamationmark.triangle` at **32 pt (26) / 48 pt (older)**; callout label, centred, secondary [B 0x100270e94, 0x100270fb4].

### 4.6 Selection, hover, keyboard focus, multi‑select
- **Selection:** the 4 pt accent ring (§4.1). There is **no hover state** on cards (no tracking area or hover ivar on `ItemCell` / `BaseCell`).
- **Keyboard:**
  - From the context menu's key equivalents (§4.8): Return pastes; Space previews; ⌘C copies; ⌘E edits; ⌘R renames; Delete deletes; ⌘O opens.
  - Arrow keys move the selection [U — handled in `CollectionView+Input`, not fully traced].
  - Typing starts a search (§2.5).
  - Tab / Shift‑Tab move focus between the search field and the strip [B fn_100096220].
- **Multi‑select** (`CollectionView.SelectionMode`) [B 0x10024560c]:

| Modifier | Mode |
|---|---|
| ⇧ | `range` |
| ⌘ | `toggle` |
| none | `single` |

  The header shows "%@ Selected" for multiple items [S `general.selected-format`].
- **Dimmed:** a selected card in a dimmed collection shows a grayscale ring (trigger [U]; probably the panel losing key or the search popover being open).

### 4.7 Scrolling, drag and animations
- **Scrolling:**
  - The strip scrolls **horizontally only**: vertical mouse‑wheel deltas are rewritten to horizontal (`NoShiftHorizontalScrollView`).
  - Horizontal elastic bounce; no vertical bounce; scrollers hidden; no background [B 0x10025125c, 0x100246a5c].
- **Scroll‑to‑selection** [B 0x100247568, 0x10021b3a8]:
  - Animated, with duration = time since the previous move, capped at **0.25 s**, and instant if under 0.1 s.
  - Curve **cubic‑bezier(0.25, 0.1, 0.25, 1)**.
- **Insert / delete / move:** default duration, ease‑out; new cells fade in [B 0x10024115c, 0x100241200].
- **Size‑class change:** animates 0 → 1 over **0.2 s**, cubic‑bezier(0.25, 0.1, 0.25, 1) [B 0x10022b600].
- **Drag:**
  - Pressing a selected card waits **0.45 s** before a drag can start; threshold **3 pt** [B 0x1002457ac, 0x100245bf0].
  - Drag image opacity 0.8.
  - Reorder insertion marker: **4 pt** wide, radius 2, `keyboardFocusIndicatorColor` [B 0x100243f5c, 0x100248a7c].
  - Auto‑scroll within 30 pt of an edge at (30 − d) / 30 × 15 pt per tick [B 0x100244040].

### 4.8 Card context menu (right‑click), in order [B 0x1000a7cf4]

| # | Title | Key | SF Symbol |
|---|---|---|---|
| 1 | "Open" / "Open with %@" | ⌘O | `arrow.up.forward.square` |
| 2 | "Reveal in Finder" (files) | — | `finder` |
| 3 | "Show in %@" — one item per list containing the item; the first gets ⌘G | ⌘G | `clock.arrow.circlepath` (history), `circlebadge` (pinboard), `circlebadge.2` (shared) |
| — | separator | | |
| 4 | "Paste to %@" / "Paste to current app" | ↩ (no modifiers) | `doc.on.clipboard` (variant badges lock / `exclamationmark.triangle`) |
| 5 | "Paste as Plain Text" | key 0x0A + plain‑text modifiers | `text.justify.leading` |
| 6 | "Copy" | ⌘C | `doc.on.doc` |
| — | separator | | |
| 7 | "Edit" | ⌘E | `pencil` |
| 8 | "Rename" | ⌘R | `pencil.and.ellipsis.rectangle` |
| 9 | "Delete" | ⌫ (no modifiers) | `trash` |
| — | separator | | |
| 10 | "Pin" ▸ | — | `pin` |
| — | separator | | |
| 11 | "Preview" | Space | `eye` |
| 12 | "Share" ▸ (system share services) | — | `square.and.arrow.up` |

- Icons are attached **only on macOS 26+**; older systems show the menu without icons.
- When the licence is locked, a lock icon replaces the item icons.
- **Pin submenu** [B 0x1000a68a0]:
  - one item per pinboard, each with a 12 pt colour dot
  - separator
  - "Create Pinboard" (`plus`)
  - "Unpin"
- Delete of shared items asks first [S `alert.delete-shared-item*`, `alert.delete-selected-items.title`].

### 4.9 Empty states and the Intelligent Clipboard placeholder
- **Empty strings:** "History is empty", "Pinboard is empty", "Nothing found" [S `empty-state.*`].
- **Empty-state style:** 26 pt regular, `ink26`, centred, −17 vertical offset [B 0x100019e54, 0x100019fb4].
- **Intelligent Clipboard prompt** (`PicksPlaceholderView`):
  - title 15 semibold `labelColor`
  - subtitle 13, secondary, max width 460
  - vertical spacing 6 (10 after the icon and the subtitle)
  - buttons "Allow Screen Access" and borderless "Turn Off", spacing 10
  - [B 0x10001aab0, 0x10001a2f4, S `intelligence.suggestions.*`]

---

## 5. Sidecar (notification / collaboration cards at the strip's left)
- **Placement:** laid out before the item cards at y = 24, left inset 24, spacing 24 [B fn_1002896ec].
- **Size:**
  - Card height = content height.
  - Width = **200** when height > 200, otherwise square; minimum 80×80 [B fn_100289fb8].
  - Same 280 / 240 / 200 size-class thresholds as the item cards.
- **Base cell, regular vs compact** [B fn_1002851cc]:

| | Regular | Compact |
|---|---|---|
| Icon inset | 12 | 10 |
| Icon size | 28 | 20 |
| Title gap | 8 | 4 |
| Symbol | 22 pt | 15 pt |
| Title | title3 semibold | body semibold |

  Subtitle is medium weight in both.
- **Corner radius:** **16 (26) / 10 (older)** [B 0x1002850c0].
- **Buttons:** capsule, normal `ink05` / highlighted `ink10`, content inset 6 × 12 [B fn_100287744].
- **Close button:** `xmark` in `ink26` / `ink50` [B fn_10028b900].
- **Notification copy** [S `notifications.*`] — for example "Enable Direct Paste", "Enable iCloud Sync", "Open at Login", "Run in Background", "Enjoying Paste?", "Meet Intelligent Clipboard", "Paste in Liquid Glass", "Shared Pinboards", trial notices.

---

## 6. Preview (Space / "Preview") and edit mode

### 6.1 Popover and window
- **Popover** (`ItemCollectionView.PreviewPopover`, an `NSPopover`):
  - transient, animated
  - shown from the selected card's bounds with **preferredEdge = maxY**, so it sits above the strip [B 0x1000ada54]
  - detachable [B 0x1000ae890]
- **Detached window** (`ItemPreviewWindow`, an `NSPanel`) [B 0x10002e7b4–888]:
  - `styleMask 0x801B` (titled, closable, resizable, utility, full‑size content)
  - traffic lights hidden, transparent titlebar, movable by background
  - **level 3 (floating)**, `hidesOnDeactivate = NO`, animationBehavior 2
  - One window per item [B 0x100011df0].
- **Size:**
  - Initial **(screen width × 0.25 + 10, screen height × 0.25 + 76)** [B 0x1000b37b4].
  - Minimum **380 × 240** [B 0x1000b1f78].

### 6.2 Headers
- **Preview header** (height **38**) [B 0x1000b1ce4, fn_100070e84–0x100071570]:
  - Close: `xmark.circle.fill`, borderless, `ink85` @ 0.6, at +10.
  - Title: headline font; double‑click renames ("Tap to rename" on iOS).
  - Trailing action stack (spacing 8, trailing −8), all ToolbarButtons:
    - **Edit** (text)
    - **Pin** (`circle.dashed` / `circle.fill` in the pinboard colour)
    - **Share** (`square.and.arrow.up`)
  - Content border: `ink10`, width 0.5, radius 5 (only for some content types).
- **Editor header** (height 38) [B 0x1000b413c–4830]:
  - Cancel (tooltip "Discard changes")
  - Writing Tools (`apple.writing.tools`)
  - Save (⌘S, tooltip "Save changes")
- **Edit titles** [S]: "Edit Text", "Edit Image", "Edit Link", "Edit Color", "Edit Item".

### 6.3 Content views and footers (`PasteCoreUI.*ItemContentView`)
- **Footer:**
  - Insets 11 / 12 / 11 / 12 [B 0x100271e00].
  - Backdrop `NSVisualEffectView`, material 5 (menu), blending within window [B 0x1002650bc].
  - A `FooterStyle` enum has `glass` and `plain` cases [U wiring].
- **Text:**
  - Footer shows "N characters · N words · N lines" [S `editor.*-count`], monospaced‑digit body, `ink50`, spacing 8 [B 0x1002312a4–8e4].
  - Editor toolbar: **Bold ⌘B, Italic ⌘I, Underline ⌘U, Strikethrough** (tooltip "Title (shortcut)"), spacing 4 [B 0x10022f978].
  - Text inset 8 × 10 [B 0x100232c54].
- **Image:**
  - Footer "W × H" in body `ink50` [B 0x1002776d0].
  - Zoomable view on a checkerboard; Live Text OCR is enabled (`isTextRecognitionEnabled`).
  - Edit: **Rotate Left ⌘L / Rotate Right ⌘R**; strings also exist for Remove / Restore Background [S] (call site [U]).
- **Link:** `WKWebView` preview with a loader; footer shows title and URL.
- **Colour:**
  - Large swatch.
  - Format rows "label · value": **HEX** (`#%06X`), **RGB** (0–255), **HSL** (360 / 100 / 100) [B 0x100385494, 0x100272fe8].
  - Editor value in fixed‑pitch 22 pt; `NSColorPanel` for editing.
- **Files:** QuickLook (`QLPreviewView`); footer shows file size via `ByteCountFormatStyle(.file)` [B 0x10027554c]; "Reveal in Finder".
- **Unknown:** `exclamationmark.triangle`, "Preview unavailable" (title2 medium) plus the explanatory subtitle (body, `ink50`) [B 0x10027e1d4, S `preview.unavailable.*`].

## 7. "New Text Item" window (`CreateItemWindow`)
- **Window:** `NSPanel` `0x801B`, traffic lights hidden, transparent titlebar, movable by background, **min 500 × 360**, level 3, centred, animationBehavior 3 [B 0x1000b59f0, 0x1000253f8].
- **Header** (38): Cancel ("Discard changes") and **Create** (⌘S, "Create text item") [S `create-item.*`].
- **Editor border:** `ink10` 0.5, radius 5.

## 8. Toasts / HUD (`PasteUI.OSDPresenter`)
- **Container:** `NSVisualEffectView`, material **13 (hudWindow)**, blending behind window, active, **corner radius 20**, content **200 × 200** [B 0x100251b10].
- **Window:** borderless `NSWindow`, level **1000**, clear background. Centred horizontally at **y = screen.minY + 140** [B 0x100251da0].
- **Timing:** stays **1.0 s**, then fades to 0 over **0.5 s** ease‑out, then `orderOut` [B 0x100251fe0, 0x10025174c].
- **Content:** template SF Symbol at **86 pt**, title in `.title`, optional subtitle in `.body` [B 0x10025294c].
- **Uses:**

| Symbol | Title | Evidence |
|---|---|---|
| `checkmark` | "Copied" (optional subtitle "Enable Direct Paste ›") | [B 0x100018358] |
| `pause` | "Paste Paused" | [B 0x100094200] |
| `arrow.clockwise` | "Paste Resumed" | [B 0x100093d84] |
| `checkmark` | "Enabled" | [B 0x1000994d4] |

  With nothing to paste, the app plays `NSSound.beep`.

## 9. Paste Stack panel (storyboard `PasteStack.storyboardc`)
- **Window:**
  - **322 × 372** template; `styleMask 0x8081` (titled, non‑activating, full‑size content), title hidden [R ib.json].
  - At runtime: **level 25** (status), `collectionBehavior 257` (canJoinAllSpaces + fullScreenAuxiliary), movable by background, frame autosave `com.wiheads.paste.paste-stack-frame` [B 0x100084754–7f4].
- **Background:** `NSVisualEffectView` material **6 (popover)**, behind window [R].
- **Header:**
  - Title **"Paste Stack"**, bold system 13, `labelColor`, centred, 8 from the top.
  - Close button (leading +8): `NSStopProgressFreestandingTemplate` 16×16.
  - Direction toggle (trailing −8): `icon.sort-up` / `icon.sort-down` 16×16 [R]. Direction is stored in the default `pasteStackDirection` (top / bottom) [B 0x1000929ac].
- **List:**
  - `NSTableView` 8 below the title, edge to edge.
  - **Row height 44**, separator grid in `separatorColor`, clear background.
  - Window height follows the row count [R, B 0x10008e540].
  - Cell: type icon (`icon.file` / `icon.link` / `icon.text` / `icon.unknown` 20 pt) and text up to 2 lines [B 0x100092ad4].
  - Swipe action "Delete" (destructive).
- **Empty state:** "Empty" in `tertiaryLabelColor`, system 13, 12 from the bottom [R].

## 10. Menu bar icon and menu
- **Icon:**
  - Template images `StatusItem/0` … `StatusItem/16` (22×22 @1x) [R]. Frame 0 is the resting logo: rounded square with the Paste "P"/arrow glyph.
  - On copy the frames play at **1/48 s per frame** [B 0x10001e484]: the logo fades out (frames 1–5), a tilted card drops in (6–9), the glyph scales back (10–16).
  - `StatusItem/paused` (24×25) adds a pause badge [R `_sheet_statusitem.png`].
- **Clicks:** left click toggles the panel; right‑click or Control‑click opens the menu [B 0x10001e8dc–984].
- **Menu** [B 0x100030c08] (separator positions approximate [U]):

```
About Paste                         info.circle
—
New Text Item               ⌘N      square.and.pencil
Settings…                   ⌘,      gear
—
Help ▸                              questionmark.circle
    Getting Started                 flag
    Keyboard Shortcuts              keyboard
    Help Center                     lifepreserver
    —
    Product Updates                 app.badge
    Feature Request                 lightbulb
    —
    Contact Support                 paperplane
    —
    Start Diagnostics / Stop and Copy Logs   ladybug
Paste on Twitter                    at
—
Pause ▸ (Paused until HH:mm)        pause.circle
    Pause Paste / Resume    ⌘T
    —
    Pause for 15m / 30m / 1h / 3h / 8h      15.circle 30.circle 1.circle 3.circle 8.circle
—
Quit Paste                  ⌘Q      xmark.app
```

  - Pause durations are 900 / 1800 / 3600 / 10800 / 28800 s, formatted with an abbreviated `NSDateComponentsFormatter` [B 0x100032060].
  - Strings come from [S `general.*`, `diagnostics.*`].

## 11. Settings window
- **Window** [B 0x1000464dc]:
  - `styleMask 0x8007` (titled, closable, miniaturizable, full‑size content), empty `NSToolbar`, transparent titlebar.
  - `NSSplitViewController`:
    - **sidebar** fixed width **200** (SwiftUI list, not collapsible)
    - **content** fixed width **440**
  - Window width is therefore **640**; height follows content [U].
- **Sidebar panes**, in `SettingsPaneID` order:

| Pane | SF Symbol | Evidence |
|---|---|---|
| General | `gearshape` | [B 0x1000b04c8] |
| Privacy | `hand.raised` | [B 0x10005201c] |
| Shortcuts | `keyboard` | [B 0x10005201c] |
| Intelligence | `sparkles` | [B 0x1000c1644] |
| Subscription | `checkmark.seal` | [B 0x1000b5548] |
| Help | not resolved | [U] |

  - Rows are `Label(title, symbol)`, symbol at 14 pt.
  - Warning badge: `exclamationmark.circle.fill`, 16 bold, red.
  - Footer button: 16 pt padding, 40 % opacity when the window is inactive [B 0x1000ac5e0, 0x1000ac220].
- **Pane chrome:**
  - Title bar 52 pt on `NSVisualEffectView` (material 12 headerView, within window); title **title3 medium**, leading 30 [B 0x10004255c, 0x100042d58].
  - Content: horizontal padding 20.
- **Group box:**
  - Title body semibold; subtitle subheadline, secondary.
  - Spacing 10, padding 10.
  - Background `ink85` at alpha 0.03, **radius 12** [B 0x10005ce88].
- **Row description:** callout.

**General** [S, B 0x1000692c0–0x10006f004]
- Switches:
  - **Open at login**
  - **iCloud sync**, with status line "Synced / Syncing / never" in callout secondary
  - **Show in Menu Bar**
  - **Sound effects**
- **Paste Items** radio cards:
  - Options **"To active app"** and **"To clipboard"**.
  - Illustrations `copy-to-app` / `copy-to-clipboard`, 64 tall, radius 8; info text below in subheadline secondary.
  - Selection background radius 5, padding 6.
- **Allow Accessibility Access** row with a red `exclamationmark.circle.fill` and `chevron.right`.
- Checkbox **"Always paste as Plain Text"**.
- **Keep History:** slider 1–5 with 5 ticks, last stop "Unlimited" with a warning tooltip [S `onboarding.macos.clipboard-history.unlimited-tooltip`]. **Erase History…** opens an alert [S `alert.erase-history.*`].

**Privacy** [B 0x100084c00–0x100087700]
- **Ignore Applications** list: app icon and name; "No items" when empty; footer +/− buttons, 24×24.
- Switches:
  - **Show During Screen Sharing**
  - **Generate Link Previews**
  - **Ignore confidential content**
  - **Ignore transient content**

  Each has the subtitle text from [S `settings.privacy.*`].

**Shortcuts** [B 0x100089700]
- Recorders:
  - **Activate Paste** (default ⇧⌘V [S onboarding body])
  - **Activate Paste Stack**
  - **Show next Pinboard**
  - **Show previous Pinboard**
- Modifier pickers:
  - **Quick Paste** (suffix "+ 1...9")
  - **Plain Text mode**
- **Reset shortcuts to default** with a confirmation.
- Recorder states: "Recording", "None", and error texts [S `shortcut-recorder.*`].

**Intelligence** [B 0x1000c2300]
- **Clipboard** section:
  - **Intelligent Clipboard** switch.
  - "Requires Apple Intelligence" tile.
  - **Allow Screen Access** row.
- **MCP tools** section (title from [S `settings.intelligence.mcp.section.title`]):
  - **Enable MCP**, with a 6 pt green status dot.
  - **MCP Server Port** field (rounded border) with a warning.
  - Connected tools list with 16×16 client icons (the five `mcp.icon.*` assets; fallback `puzzlepiece.extension`).
  - Connect sheets 360 / 430 / 320 wide.

**Subscription** [B 0x100006c00]
- App icon 60×60, "Paste" title3 semibold, **Manage** button.
- Header "One Subscription, Endless Productivity" with the `subscription` illustration.

**About** [B 0x10000c000]
- Icon 120×120, "Paste" title bold, "Version X (build)".
- Social buttons: twitter, facebook, mastodon, linkedin (12 pt glyphs, `ink50`).

## 12. Onboarding (PasteOnboarding)
- **Window** [B 0x10023c764, 0x100a1a91c]:
  - Standalone (`GlassBackgroundWindow` on 26).
  - Style `0x8003`, title hidden, transparent titlebar, minimise/zoom hidden, movable by background.
  - Container **544 × 652** [B 0x100a19760]; page transition ease‑in‑out **0.3 s**, move from edge.
- **Intro page:**
  - App icon **160×160**, animated between pages.
  - **"A Better Way to Copy and Paste"**, **22 bold**.
  - Subtitle 13 regular ("Paste is a time machine for your Clipboard…") [S `onboarding.macos.introduction.*`].
  - Default button **Get Started**.
- **"Quick Start"** setup page:
  - Icon 80×80, title 22 bold, subtitle "Set up and start using Paste." (13).
  - A **400 wide**, radius‑10 card (`ink02` background); rows padded 12 × 10 with dividers:

    | Row | Control | Subtitle |
    |---|---|---|
    | Run in background | switch | "Open at login and always keep running" |
    | iCloud sync | switch | "Securely sync your data across all devices" |
    | Activation shortcut | recorder, width 120 | "Instantly access Paste in any app" |
    | Clipboard history | slider | "How long to retain copied content" |

  - Default button **Continue** [B 0x100a1c800].
- **Help onboarding pinboard:** the "Welcome Aboard" pinned items use `onboarding.*` images (640×360) [R PasteCore bundle].

## 13. What's New
- **Current ("Intelligent Clipboard")** [B 0x10025efbc–0x100260c34]:
  - Width **544**; padding top 32, bottom 92, sides 72; spacing 24.
  - Image `whats-new` **400×300**, radius 20; icon 80×80.
  - Title "Intelligent Clipboard"; description [S `whats-new.description`].
  - Buttons (max 160 wide each, spacing 8): **Continue**, **Learn More**, **See it in action** (`play.circle`), **Rate on App Store**.
  - Escape cancels.
- **V5 migration screen** [B 0x100020250–0x100023fc0]:
  - `whats-new-v5` 400×300; Continue 120 wide.
  - Progress 160×40.
  - Status icons at 72 pt: `exclamationmark.triangle` orange / `xmark.circle` red / `migration-complete` image.

## 14. Permission screens (PasteSystemPermissions)
- **Window:** content **544 × 680** [B 0x1009fed3c].
- **Layout:**
  - icon 80×80
  - title (`.title` bold)
  - subtitle (body)
  - illustration **400×200**, radius 10 (`enable-accessibility-access`, `enable-pasteboard-access`, `enable-screen-recording-access`)
  - buttons: Cancel (Esc) and primary default
- **Granted state:** `checkmark.circle` 64 pt green.
- **Strings:** "Paste to Any App" / "Allow Access" / "Not Now" / "Open System Settings" / "I'm Having an Issue" [S `accessibility-access.*`].
- **Direct‑paste prompt** (`PasteToOtherAppsView`):
  - Width 280, image `paste-to-other-apps` 280×160.
  - "Do you want to paste directly to %@?" (title2 bold).
  - Buttons "Allow Accessibility Access" / "Not Now, Copy to Clipboard"; "Do not ask again" toggle.

## 15. Button styles (SwiftUI, PasteUI) [B 0x10021d800–0x10021e400]
- **Variants:** styles `filled` / `gray` / `plain`; sizes `medium` / `large`.
- **26:** system `GlassButtonStyle` / `GlassProminentButtonStyle`. Label **13 medium**; padding horizontal 20 (large) / 16 (medium), vertical 10.
- **Older:**
  - Rounded rectangle, radius 10.
  - Filled = `systemBlue` with white @ 0.9 label.
  - Pressed: scale 0.99, brightness −0.1, opacity 0.5.
  - Focus stroke: accent @ 0.25, 0.75 wide.

## 16. Sounds
- **Copy.aiff:** 0.207 s, stereo, 44.1 kHz [R afinfo]. Plays on capture (`pasteboardHistoryManagerDidCaptureItem`).
- **Paste.aiff:** 0.080 s [R afinfo]. Plays on paste / restore (`…DidRestoreItem`).
- Both use `AudioServicesCreateSystemSoundID` and are gated by **Sound effects** [B 0x100025910–0x100025fc8].

## 17. Effects (`default.metallib`)
- **Shader pairs** [R]:
  - `glowVertex` / `glowFragment`
  - `picksIconVertex` / `picksIconFragment`
- **`IntelligenceGlowView`:**
  - Additive‑composited (`compositingFilter = additionCompositing`) [B 0x1000de474].
  - Animated flame/noise glow band around the panel while Intelligent Clipboard suggestions load or show.
  - Scenes `closed` / `loading` / `open`; spring easing, including an ease‑out‑back constant 1.70158 [B fn_1000dfa64].
- **`PicksIconView`:** Metal "blob" icon for the Picks button that reacts to the pointer; model data comes from the asset‑catalog data sets `picks-model` / `picks-modes` [R].
- There are **no blur shaders**. Liquid Glass comes from `NSGlassEffectView`; older systems use flat or vibrancy views.

## 18. Rendered reference images (reference only — not for the repo)

All files are in `scratchpad/paste/assets/`: @2x PNGs plus `_dark` variants where the catalog has DarkAqua, and two contact sheets (`_sheet_statusitem.png`, `_sheet_illustrations.png`).

| Asset | Pixels | Description |
|---|---|---|
| `StatusItem_0…16` | 44×44 | Menu bar animation frames (template) |
| `StatusItem_paused` | 48×50 | Logo with pause badge |
| `icon.file`, `icon.link`, `icon.text`, `icon.unknown` | 40×40 | Paste Stack row icons (template, 20 pt) |
| `icon.sort-up`, `icon.sort-down` | 36×28 | Paste Stack direction toggle |
| `icon.unknown-app` | 168×168 | Header app icon fallback |
| `copy-to-app`, `copy-to-clipboard` | 192×128 | Settings "Paste Items" cards: strip and window sketch with an arrow; "Copied" check |
| `whats-new` | 800×600 | Mail compose window with the macOS 26 strip and link/image cards |
| `whats-new-v5` | 800×600 | Collage: "5.0", Shared Pinboards, iOS |
| `migration-complete` | 720×320 | Mac and iPhone with green check and "5.0" badges |
| `subscription` | 688×272 | App‑icon cluster |
| `AccessibilityAccess` | 854×649 | Legacy System Settings screenshot with "1. Unlock changes / 2. Enable Paste" callouts |
| `enable-accessibility-access`, `enable-pasteboard-access`, `enable-screen-recording-access` | 800×400 | System Settings crops on an orange wallpaper |
| `paste-to-other-apps` | 560×320 | Direct‑paste prompt illustration |
| `mcp.icon.*` (5 assets) | 128×128 | MCP client icons |
| social icons | small | dribbble, facebook, linkedin, mastodon, medium, twitter |
| `AppIcon`, onboarding `Icon` | 256×256 | App icons |
| `onboarding.get-started.mac`, `get-mac-app`, `help-support`, `stay-tuned` | 1280×720 | Onboarding pinboard images |
| `PasteboardAccess_tutorial1`, `SaveExtension_tutorial1` | — | iOS tutorial art |
| `direct-paywall` | 800×414 | Paywall art |

---

## 19. Gaps (not determinable statically)

**Naming and token gaps**
- **Token names.** Palette, Geometry and font helpers are anonymous in the stripped binary. The names here (`ink85`, `surface1`, …) are ours.
  - Which `Geometry` getter (20 / 6 / 12 / 14 / 16 / 18 / 22 / 160) is spacing, radius or icon size is unknown.
  - Usage sites were not found for the surfaces #F2F2F7 / #1C1C1E, #2C2C2E or #767680.
- **Text-style point sizes.** These are macOS's defaults (§1.2) and were not read from the binary. Paste requests text styles, so sizes follow the system.

**Panel and top-bar gaps**
- **Exact rendered look of Liquid Glass.** `NSGlassEffectView` tint/style properties beyond `cornerRadius` were not traced. No `style` or `tintColor` setter was seen on the strip's glass.
- **Search field height.** It is implied by its content: a 20 pt input plus a 16 pt clear button. Treat ~28 pt as [U].
- **Tab bar:** chip height 28 is derived; the tab-context-menu order and separators are unknown.
- **Picks button:** bounce scale values unknown.
- **ToolbarButton:** meaning of the init flag that adds a pull-down.
- **Search suggestion rows:** row corner radius unknown.
- **Filter-browser popover:** edge unknown.
- **"Closed state" reset:** exact behaviour after the 10 s timer.
- **"Dimmed" collection:** exact trigger.

**Card gaps**
- **Default modifiers.** The default quick-paste and plain-text modifiers are stored defaults, not constants. The UI says "⌘1–9"-style and ⇧⌘V for activation [S onboarding].
- **Keyboard navigation:** the full map (arrow keys, Home/End, page keys) was not traced.
- **Title rule:** when a card shows a custom title versus the type label.
- **"Show in …" menu item:** when it appears.
- **Share submenu:** which item types get it.
- **Link cards:** exact favicon offsets in compact mode.

**Secondary-window gaps**
- **Footers:** the glass vs plain `FooterStyle` wiring.
- **Colour editor:** the third format's label (only HEX / RGB / HSL were confirmed).
- **Image editing:** where "Remove Background" is called.
- **Preview window:** footer height constraint.

**Settings and onboarding gaps**
- **Settings window:** title and frame autosave name; the Help pane's symbol and contents.
- **Keep History slider:** the stop labels (5 stops, the last is "Unlimited").
- **SwiftUI screens:** on-screen visual order can differ from code order.
- **Permission screens:** outer padding.
- **Older-system button style:** which branch gives radius 100.

**Menu-bar gaps**
- **Status icon:** which event triggers the copy animation.
- **Menu:** exact separator positions.
- **Main menu:** whether an app main menu exists (the app is LSUIElement).

**Runtime-only values** (need a running instance, which was out of scope)
- Live sizes driven by Auto Layout intrinsic content, such as tab widths, the sidecar content height and the popover content size.
- Actual app-icon colours per app.
- Animation feel beyond the durations and curves listed.
