# UI direction

## The reference

Norton Utilities for System 7 / Mac OS 8: a launcher window that is itself the
product — a consistent menu of tools, each with a friendly icon and a one-line
description ("Diagnose and repair damaged disks"), each opening its own
focused window. The charm is that it feels *approachable*: bright chrome,
clear labels, nothing hidden, nothing alarming.

## Why Rigi (over osmium-ui)

Two fleet assets recreate the era: **osmium-ui** (pixel-perfect Mac OS 8 in
HTML/CSS for web pages and WKWebView) and **Rigi** (native AppKit classic
controls extracted from Lucerne, shared with Sion). Chosen: **Rigi**.

- Native: accessibility, keyboard navigation, focus, and text scaling come
  free instead of being re-implemented inside a web view.
- Already proven: two shipped apps use it; `RigiGallery` demos every control
  (`swift run RigiGallery` in that repo).
- The right granularity: module panes are SwiftUI (what the fleet already
  writes); Rigi supplies the *chrome* — bars, wells, palettes, window shape —
  via `NSViewRepresentable`, which is exactly how `StatusBar.swift` already
  bridges it.
- Pinned to an immutable commit in `Package.swift` (no tags yet) — bumps are
  deliberate.

osmium-ui stays useful as the *pixel reference* — when a Rigi control needs a
shade or a hairline, osmium's CSS is the spec to check.

## Anatomy of the home window

Norton's menu window, mapped to components that exist today:

| Norton element | Implementation |
| --- | --- |
| Window with the classic silhouette | `ClassicWindow` (pre–Big Sur corner shape) or a standard SwiftUI window until the chrome pass |
| Tool rows: icon + name + one-liner | Home-view tiles today → row list later (icons 32–48 px, name in small headline, summary in caption) |
| Engraved status footer | `StatusBarView` (already bridged) |
| Inset list wells | `ClassicInsetBox` around scroll content |
| Toolbar/segmented chrome | `ClassicBarView`, `ClassicSegmentedControl`, `ClassicToolbarButton` |
| Utility palettes inside tools | Rigi's detachable palettes, per module |

The suggestion feed sits above the grid — the one modern element Norton never
had, dressed in the same chrome so it reads as "the suite noticing things",
not a notification center bolted on.

## Icons

- Placeholders today are SF Symbols; they read as modern-macOS, not classic.
- The real grammar: friendly, slightly tactile tool icons — the four muted
  squares in the provisional app icon (`media-sources/icon.py`) gesture at
  the palette (steel blue, olive gold, terracotta, sage — colors that sit
  comfortably on platinum).
- Keep per-tool icon identity from the standalone apps where it's good
  (RepoMen's, Coreography's artwork) rather than redesigning the set at once.
- Pict is the fleet's icon store — use it for management/export when real
  icons are drawn.

## Modern manners (what NOT to copy from 1997)

- **No modals for findings.** Suggestions live in the feed and menu; alerts
  only for destructive confirmations.
- **Keyboard + VoiceOver are first-class**: grid is fully navigable,
  suggestions expose their deep link as an action.
- **Light only — decided.** The app always renders aqua, enforced by
  `NSRequiresAquaSystemAppearance` in `Info.plist`, whatever the system
  appearance. Rationale: the classic look *is* light platinum — a dark
  variant is a redesign (charcoal chrome, re-tuned tile colors, re-checked
  engraving contrast), not a reskin, and the suite has no business paying
  that while modules are still unmigrated. If it is ever revisited it is a
  product decision plus Rigi work — not per-screen dark patches, which is how
  apps end up with the worst of both.
- **Subtlety over skins**: the classic look lives in chrome, typography scale
  and the grid — not in texture overload. If a screen needs four kinds of
  bevel to feel classic, it's wrong; two is enough.

## First milestone for the eye

The scaffolding's home screen is SwiftUI-flat today. The first "does it feel
right" checkpoint: home window with `ClassicInsetBox`-wrapped grid, Rigi
status bar, suggestion feed section, one migrated pane (DockVac's treemap) —
that screenshot should be unmistakably "Norton, but polite".
