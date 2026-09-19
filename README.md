# MaracaShelf

A background macOS utility: hold down a file you're dragging, shake the cursor back and
forth, and a floating "shelf" appears right under the cursor, on top of every window and
every desktop. Drop files into it, then drag them out of the shelf into any app. Close the
shelf and every temporary copy is deleted — the originals are never touched.

## Installing

### From a zip (recommended)

Grab the latest `MaracaShelf-X.X.X.zip` from
[Releases](https://github.com/mentalLonnieov/maracashelf/releases), then:

1. Unzip it and move `MaracaShelf.app` wherever you like (`/Applications` is the usual
   choice).
2. **Bypass Gatekeeper.** This build is signed ad-hoc (no Apple Developer ID, not
   notarized), so macOS blocks it on first launch. On recent macOS (Sequoia/Tahoe and
   later), the classic right-click → Open trick often isn't enough by itself — instead:
   - Try to open it (double-click). You'll get a "can't be opened" warning.
   - Open **System Settings → Privacy & Security**, scroll down to the line about
     "MaracaShelf" being blocked, and click **Open Anyway** (you may be asked for your
     password or Touch ID).
   - Or, more reliably regardless of macOS version, clear the quarantine flag yourself in
     Terminal:
     ```bash
     xattr -d com.apple.quarantine /Applications/MaracaShelf.app
     ```
3. **Grant the Accessibility permission** — see below. The system should prompt for this
   on first launch; if it doesn't, use the menu icon's "Open Accessibility Settings…" item.

### Via Homebrew

```bash
brew tap mentalLonnieov/maracashelf
brew install --cask maracashelf
```

This build is signed ad-hoc (no Apple Developer ID, not notarized), and Homebrew Cask
applies the quarantine flag to installed apps just like a normal download would, so macOS
will still block the first launch. Clear it with:

```bash
xattr -dr com.apple.quarantine /Applications/MaracaShelf.app
```

(`brew install` prints this exact command at the end, with the real path filled in — you
can copy it straight from there.) You'll also need to grant the Accessibility permission
(see below); the system should prompt for it on first launch.

To update or remove it later:

```bash
brew upgrade --cask maracashelf
brew uninstall --cask maracashelf
```

## Building from source

```bash
Scripts/build_app.sh release
open MaracaShelf.app
```

The app runs with no Dock icon (menu bar icon only — a maraca,
`Resources/MaracaStatusIcon@2x.png` and `@3x.png`, a template image that adapts itself to
the menu bar's light/dark appearance). `Scripts/build_app.sh` copies them into
`Contents/Resources` at build time; when running the raw debug binary directly (not through
the packaged `.app`), those files aren't available and `AppDelegate.loadStatusIcon()`
silently falls back to the system `shippingbox` symbol.
The menu icon's menu lets you open Settings (shake sensitivity + interface language),
open Accessibility settings, or quit.

The `.app` bundle itself (as seen in Finder, Get Info, Spotlight) has its own separate icon
— a glossy blue maraca on a light gray gradient, `Resources/AppIcon.icns`, wired up via
`CFBundleIconFile` in `Info.plist` (see `Scripts/build_app.sh`). This is unrelated to the
menu bar image above: that one is a flat black-and-white *template* image (so macOS can
tint it for the menu bar), while this one is a full-color 1024×1024 source flattened into
the standard `.icns` size set via `iconutil`. macOS 26 Tahoe also introduced a newer
multi-layer "Liquid Glass" icon format (built with Xcode's Icon Composer, giving icons
depth/parallax) — this project doesn't use it since it's built with plain `swift build`,
not Xcode; a standard flat `.icns` still renders correctly on 26/27, just without that
extra dynamic depth effect.

## Settings window

Menu icon → "Settings…" opens a window styled the same way as the shelf — a borderless
card with the same Liquid Glass (`GlassChrome`) and its own "×" button instead of the
system one — but unlike the shelf it does become a key window (it's an ordinary settings
window, not a drag & drop overlay; see `KeyableBorderlessWindow`). It has four sections
under an overall "Settings" title:

- **Shake Sensitivity** — a slider from "needs a strong shake" to "a light shake is
  enough". The value persists across launches (`UserDefaults`, key `ShakeSensitivity`) and
  applies immediately, no restart needed — `ShakeDragMonitor` reads it on every gesture
  check (see `ShakeSensitivity.swift`). The default value (50%) matches the detector's
  original hardcoded thresholds.
- **Interface Language** — see below.
- **Storage** — the archive's auto-delete window; see "Archive" above.
- **Shelf Size** — "Default" (3-column grid) or "Compact" (2 columns, roughly a 2×2 view
  before scrolling); see "How it works" below. Unlike sensitivity/language, this only takes
  effect for the *next* shelf you open — an already-open one keeps its size.

(The window's own title and each section header share one label style —
`SettingsWindowController.titleLabel`, i.e. "Shake Sensitivity", used to be styled as the
window's title before the language section existed; once there were two sections it was
demoted to match, and a new `windowTitleLabel` ("Settings") was added above both.)

## Localization

The UI ships in six languages: English, Russian, Ukrainian, Polish, Czech, German. On
first launch it picks whichever of those matches the system's preferred language, falling
back to English if none match. It can be overridden at any time from the settings window's
"Interface Language" section — the whole UI updates immediately, no relaunch needed.

This is handled by a custom `LocalizationManager` rather than plain `NSLocalizedString`:
`NSLocalizedString` always resolves against `Bundle.main` using the system's own language
list, which can't be overridden per-app without relaunching. Instead, `LocalizationManager`
loads whichever `Resources/<code>.lproj/Localizable.strings` bundle is currently in effect
directly (see `Scripts/build_app.sh`, which copies all six `.lproj` folders into
`Contents/Resources`) and posts a notification on change so already-built UI — the status
bar menu, an open settings window — can refresh its text in place (see
`AppDelegate.refreshMenuTitles` and `SettingsWindowController.refreshLocalizedText`).

File counts ("N files") are pluralized per language's actual grammar rather than a generic
singular/plural split — `Pluralizer.swift` implements each language's Unicode CLDR integer
plural rule: English/German only distinguish one vs. other; Russian and Ukrainian share the
same three-category Slavic rule (e.g. "21 файл" / "22 файла" / "25 файлов"); Polish and
Czech each have their own distinct variant. Verified by print-checking `fileCount(n)` for
n ∈ {0, 1, 2, 5, 11, 21, 22} against every language's real grammar rather than trusting the
formulas by inspection alone.

## Archive

Every file that passes through the shelf is also copied into a persistent archive
(`~/Library/Application Support/MaracaShelf/Archive`) — separate from the shelf's own
per-session temp copies, and unaffected by closing the shelf or quitting the app. Open it
from the menu icon's "Show Archive…" item to browse what's there, drag files back out into
another app, or remove individual ones. The window floats above other apps and follows you
to whichever desktop/Space is active, so it stays reachable while you're dragging files
elsewhere.

The archive also won't accumulate redundant copies of the same file: removing it from a
shelf and dragging it back in, or dragging the same file into a brand-new shake session
later, is recognized as the same file (see "How it works" below) and reuses the existing
archive entry instead of storing it again.

By default, archived files are deleted automatically after 7 days. Change that window
(1–30 days) from the settings window's new "Storage" section, or clear the archive
immediately with "Clear Archive Now" there (or the archive window's own "Clear Archive"
button). The archive is only ever removed by expiry, a manual clear, or fully uninstalling
MaracaShelf via the menu icon's "Uninstall MaracaShelf…" item — which deletes it and moves
`MaracaShelf.app` to the Trash. (macOS has no hook for "the user just dragged this app to
the Trash themselves," so a plain drag-to-Trash leaves the archive folder behind; the
in-app Uninstall action is the only way to remove both together.)

## Required permission

For the app to see mouse movement while you're dragging a file **from another app**
(Finder, Mail, etc.), macOS requires the **Accessibility** permission (Privacy & Security →
Accessibility). The system should prompt for it on first launch; if not, go to the menu
icon → "Open Accessibility Settings…" and enable MaracaShelf in the list.

Without this permission the shelf will only open when shaking during a drag *inside
MaracaShelf itself* (local events), not over other applications.

> The app was renamed from ShakeShelf: the bundle id changed
> (`com.local.shakeshelf` → `com.local.maracashelf`), so macOS treats it as a new app —
> the Accessibility permission needs to be granted again.

## Appearance

On macOS 26 (Tahoe) and 27, the panel and its buttons/pill use real system Liquid Glass
(`NSGlassEffectView`/`NSGlassEffectContainerView`, including the interactive click response
available since macOS 27). On older systems it falls back to the classic
`NSVisualEffectView` (`.hudWindow` material) — the logic and layout are identical, only the
background material differs (see `GlassChrome.swift`).

The system's "more transparent ↔ more frosted" slider (System Settings → Appearance,
macOS 26+) is stored in a plain user default, `NSGlassTintAmount` (`defaults read -g
NSGlassTintAmount`) — there's no public AppKit API for it yet, but `GlassChrome` reads this
value every time the shelf is shown and scales the glass tint's opacity accordingly (see
`SystemGlassSettings.swift`), so the shelf's "glassiness" tracks the system setting instead
of being fixed forever.

## How it works

- `ShakeDragMonitor` listens to global mouse events while the left button is held down and
  recognizes a "shake" — several quick direction reversals in a short time window (a
  heuristic similar to the shake gesture on iOS).
- When it fires, `ShelfPanel` opens — a non-activating (`nonactivatingPanel`) panel right
  under the cursor, `level = .floating`, with `collectionBehavior`
  `[.canJoinAllSpaces, .fullScreenAuxiliary]` — meaning it follows the active desktop and
  stays on top of windows, including full-screen apps, until you close it yourself.
- Files dropped into the shelf are copied into a per-session temp folder (`ShelfStorage`) —
  both plain `file://` URLs and promise-based drags work (Mail/Safari attachments etc., via
  `NSFilePromiseReceiver`). A successful drop triggers the standard trackpad haptic feedback
  (`NSHapticFeedbackManager`, `.alignment` style — the same one Finder uses for icon
  alignment), fired once per drop rather than once per file when several are dropped at
  once.
- Dropping a file onto the *collapsed* shelf works too, not just the expanded grid. The
  panel's whole body (`ShelfDropView`) already covers the collapsed state as well — it's
  just visually replaced by `CollapsedPreviewRow`, a plain `NSView` that wasn't itself
  registered for drag types. Unlike ordinary mouse events, dragging-destination callbacks
  aren't delivered to an ancestor when the exact hit-tested view isn't registered, so a
  drop landing on the visible collapsed row (rather than the sliver of bare panel around
  it) was silently missing before: `CollapsedPreviewRow` now also registers for the same
  drag types and forwards `draggingEntered`/`performDragOperation` straight to
  `ShelfDropView` rather than duplicating its logic — and overrides `hitTest` to always
  return itself (never one of its purely decorative icon/label subviews), so a drop
  landing squarely on an icon reaches that forwarding too.
- Dropping the same file into the shelf twice is rejected instead of piling up endless
  renamed duplicates ("file 1.ext", "file 2.ext", ...): `ShelfViewController` tracks a
  dedup key per already-added file — the source URL's standardized path for a plain file
  drag, or the proposed filename for a promise (Mail/Safari attachments don't expose a
  real source path). A rejected re-drop briefly flashes the existing thumbnail and lets the
  dragged icon snap back to its origin (returning `false` from the drop handler), rather
  than silently doing nothing. Removing a file from the shelf frees its key again, so it
  can deliberately be dropped back in.
- Dragging a file OUT of the shelf hands the receiving app the path to that temp copy.
  Multi-select works with standard macOS gestures (⌘-click to add/remove a file from the
  selection, Shift-click to select a range) — dragging out of a selection sends every
  selected file at once (`allowsMultipleSelection` on the `NSCollectionView`). Right-click
  the grid for a "Select All" context menu item — ⌘A doesn't work here since the shelf
  panel never becomes key (see `ShelfPanel`) and so never receives keyboard events at all;
  a context menu is the mouse-only equivalent. There's no
  visible scroll indicator, but scrolling itself (wheel/trackpad/drag) works normally —
  `NSCollectionView` recreates/re-shows its own `NSScroller` on every layout pass regardless
  of `hasVerticalScroller`, so instead of a one-time setup its opacity is forced to zero on
  every `viewDidLayout()` (see `ShelfViewController.viewDidLayout`); confirmed by dumping
  the actual live view hierarchy at runtime — the scroller physically exists, but
  `alphaValue == 0`.
- The shelf appearing and closing is a symmetric fade (`alphaValue` 0↔1 inside an
  `NSAnimationContext`, 0.18s/0.15s). `orderFrontRegardless()` on its own gives no
  appear animation (unlike `orderOut()`, whose `animationBehavior = .utilityWindow` already
  includes a fade) — so both directions are done explicitly instead of relying on AppKit's
  inconsistent defaults.
- A centered AirDrop button in the header (expanded state only) uses the real AirDrop glyph
  — `NSSharingService(named: .sendViaAirDrop)?.image` — instead of a generic share icon, so
  it reads as "AirDrop" at a glance. Two substitutes were tried and rejected: forcing that
  real asset into a tintable template image collapsed it into a solid blob (it's a full
  app-icon-style bitmap — an opaque rounded-square backdrop with the rings distinguished
  only by a soft gradient, no alpha separating them from the background — and template
  rendering only looks at alpha, not color); and a hand-drawn replacement (two concentric
  `NSBezierPath` arcs with butt line caps plus a dot, approximating AirDrop's notched-ring
  look) read fine enlarged but turned muddy at the actual ~18pt button size once tried for
  real. So the button keeps the real, full-color glyph and simply accepts that it won't
  react to the system's monochrome icon appearance mode (macOS 26/27) — recognizable beats
  adaptive here. It's disabled by default and
  enables as soon as at least one file is selected in the grid (`NSCollectionView`
  `didSelectItemsAt`/`didDeselectItemsAt`). Tapping it calls `NSSharingService(named:
  .sendViaAirDrop)` with every selected file, skipping the intermediate picker (it opens
  the system AirDrop window directly). `ShelfViewController` implements
  `NSSharingServiceDelegate`. Both anchoring approaches were tried separately:
  `sourceWindowForShareItems` (attaching the sheet to our window) removes the "slides down
  from the top of the screen" placement, but hosting a sheet somehow brings back the system
  key-window focus ring — the same artifact `ShelfPanel.canBecomeKey = false` was supposed
  to disable for good (meaning sheet-hosting goes through a separate code path, not tied to
  ordinary key status). So only `sourceFrameOnScreenForShareItem` is used (the AirDrop
  button's on-screen frame, with no window attached) — no ring, and no top-of-screen slide.
- The "×" button on the panel itself deletes the whole session's temp folder and closes the
  panel. For a single file (say, the wrong one got dragged in), hovering over its preview
  reveals a small "×" badge in the corner — it removes only that file, leaving the rest and
  of course the original untouched.
- If the app happens to crash or gets force-quit with the shelf open, leftover temp copies
  from the previous session are cleaned up on the next launch.
- Every file added to the shelf is also copied into a separate, persistent `ArchiveStorage`
  folder (`~/Library/Application Support/MaracaShelf/Archive`) — one UUID-named subfolder
  per file, so identical filenames from different sessions never collide. This is
  intentionally independent of `ShelfStorage`'s per-session temp copy: the temp copy is
  deleted the moment that shelf closes, the archive copy is not.
  `ArchiveStorage.purgeExpired()` deletes archive entries older than
  `ArchiveRetentionSettings.days` (default 7, 1–30 range) based on each folder's creation
  date — run on launch, hourly via a repeating `Timer`, and whenever the archive window
  opens, so it stays current even across a multi-day run with no relaunch.
- The archive dedups by the same identity key as the live shelf, but persists it in a
  `<uuid>.maraca-source-key` sidecar beside each entry folder. Older archives with an
  internal `.maraca-source-key` are still read and deduplicated correctly. User dotfiles
  remain visible, including files named `.maraca-source-key` in the new format. This makes
  "remove from the shelf, then drag the same file back in" and "drag the same file into a
  new shake session weeks later" both reuse the one archive entry instead of piling up
  duplicates, since the check reads persisted disk state rather than any in-memory set
  scoped to a single shelf.
- Copying and archive access run off the main thread. All archive requests share one
  serial queue, and new entries are published by renaming a completed staging folder.
  A file becomes interactive on the shelf after its archive operation finishes. Closing
  the shelf hides it immediately, but temporary-file cleanup waits for all accepted
  imports, including delayed file promises and their archive operations, to finish.
- "Uninstall MaracaShelf…" (status bar menu) deletes the whole Application Support folder
  and moves the running `.app` bundle to the Trash via `NSWorkspace.recycle(_:)` — waiting
  for its completion handler before calling `NSApp.terminate(nil)`, since quitting
  immediately after kicking off that async move risks cutting it short.
- Collapsing/expanding animates `NSWindow.setFrame` directly. The glass panel
  (`GlassChrome.panel`) is assigned as the window's `contentView` literally (no view in
  between) — that's the only AppKit relationship guaranteed to track an animated `setFrame`
  perfectly; any extra layer between the window and the glass (even an autoresizing-based
  one) visibly lagged behind the animation in practice. `collapsedHeight` (132pt) is chosen
  to never be smaller than the real Auto Layout minimum of the collapsed content — with a
  too-small value, the window would snap to the real minimum on the animation's very last
  frame, which looked like a jump/overshoot; every time the collapsed state's content
  changes (e.g. adding `CollapsedPreviewRow`) that minimum needs re-checking the same
  way — by logging timestamped `window.frame` samples across the animation, not by eye.
  That autoresizing-based pin (`GlassChrome.pinTrackingAnimatedResize`) is only correct for
  the *main panel*, whose container really is being resized by an outside animation.
  Applying the same trick to `control`'s small static buttons (close/collapse/remove — never
  themselves resized) fought `NSGlassEffectView.contentView`'s own internal Auto Layout
  constraints instead of just being redundant, producing a real "Conflicting constraints
  detected" warning at runtime — invisible in a plain `swift build`, but surfaced immediately
  by Xcode's build log. Fixed by splitting the helper: `pinTrackingAnimatedResize` (still
  autoresizing) for `panel`/its pre-26 fallback, `pinStatic` (plain NSLayoutConstraint,
  cooperating with NSGlassEffectView's own constraints) for `control`/its pre-26 fallback.
- While collapsed, the empty space between the header and the pill is now filled by a row
  of small previews (`CollapsedPreviewRow`, up to 5 icons plus a "+N" for the rest) — only
  visible while `isCollapsed == true`, updated whenever files are added/removed and when
  real previews finish loading via `ThumbnailLoader`. There's no room for per-file
  selection in this compact row, so pressing and dragging from *any* icon in it drags every
  file in the shelf at once (`CollapsedPreviewRow` implements `NSDraggingSource` directly,
  with manual `mouseDown`/`mouseDragged` tracking and a small movement threshold before the
  drag session actually starts, building one cascaded `NSDraggingItem` per file) — the
  collapsed state is a "grab the whole shelf" shortcut rather than a picker.
- The transition between the grid and the preview row is animated: both stay visible
  (`isHidden` is only reapplied in the `completionHandler`, once opacity has actually
  reached 0) and crossfade via `animator().alphaValue` inside the same `NSAnimationContext`
  that moves the window; the icons in `CollapsedPreviewRow` also "grow"/"shrink" — each
  one's size is animated through constraint constants + `layoutSubtreeIfNeeded()` with
  `allowsImplicitAnimation = true` (the standard AppKit way to animate Auto Layout, rather
  than `CALayer.transform`/`anchorPoint` tricks, which would be risky to combine with the
  already fragile window-animation synchronization).
- The preview grid is 3 columns by default (`panelWidth = 270`, 74×84 cells, 12pt gaps)
  instead of the original two with a big gap down the middle: `NSCollectionViewFlowLayout`
  stretches leftover space between columns once it's fit as many as it can, so the width and
  cell size were tuned so the columns fill the panel exactly, with no slack left over
  (verified by dumping the actual cell frames). That stretch is why the width formula in
  `ShelfSizePreference` uses a 12pt gap, not the nominal 10pt `minimumInteritemSpacing`
  configured on the layout — `columns*74 + (columns-1)*12 + 24` reproduces the original 270
  exactly for 3 columns, and gives 184 for the "Compact" 2-column size (Settings → Shelf
  Size). `panelWidth`/`expandedHeight` are read once when a `ShelfViewController` is created
  and stay fixed for that shelf's lifetime — changing the setting only affects shelves
  opened afterward, since resizing one already open (mid-drag, potentially) would be
  jarring. The collapsed height doesn't vary with this setting, since the collapsed
  content's actual minimum doesn't depend on the expanded grid's column count.
- Verified via the private SkyLight API (`CGSCopySpacesForWindows`) that the panel really is
  registered with the WindowServer as belonging to every current Space at once, not just the
  one it was opened on.
- `ShelfWindowController` subscribes to `NSWorkspace.activeSpaceDidChangeNotification` and
  re-calls `orderFrontRegardless()` on the panel every time the desktop switches — this
  fixes an observed "stuck on the previous desktop" glitch (the WindowServer doesn't always
  repaint an all-spaces window right after a Space switch on its own). Raising the window
  level (`.statusBar`/`.screenSaver`) was tried as an alternative fix for the same issue —
  it didn't actually solve it, and `.screenSaver` additionally broke drag & drop (very high
  levels are excluded from drag-destination hit-testing), so the level stays `.floating`.

## Known limitations

- Shake detection is a mouse-motion heuristic, not a real interception of another app's
  drag session (there's no public macOS API for that). It triggers on fast zigzag movement
  while the left mouse button is held, regardless of what's actually being dragged; a
  straight-line drag or a slow window move doesn't trigger it (verified against synthetic
  data).
- Sensitivity (`requiredReversals`, `minSwing`) is now user-configurable via the menu icon
  (see above); `windowDuration`/`cooldown` remain hardcoded in `ShakeDragMonitor.swift`, in
  case those need to become configurable too.
- The project isn't sandboxed (App Sandbox), so no security-scoped bookmark export is
  needed — but it also can't be distributed through the Mac App Store as-is.

## License

MIT — see [LICENSE](LICENSE).
