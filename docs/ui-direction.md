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

- Native controls provide a starting point for accessibility and keyboard
  behavior, not a guarantee. Rigi also has custom-drawn `NSControl` subclasses
  and fixed-size text; verify semantics, focus and scaling in the suite.
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
  that cost without a demonstrated need. If it is ever revisited it is a
  product decision plus Rigi work — not per-screen dark patches, which is how
  apps end up with the worst of both.
  Apple documents the key as a temporary opt-out and tells apps that never
  plan a dark appearance to set the app's appearance instead
  ([Choosing a specific appearance](https://developer.apple.com/documentation/appkit/choosing-a-specific-appearance-for-your-macos-app)).
  So the app also sets `NSApp.appearance = NSAppearance(named: .aqua)` at
  launch, as Lucerne does (`SuiteAppDelegate`). Rigi's colors are fixed
  light values, so a key macOS stops honoring would leave light chrome under
  dark system controls.
  The key is per-bundle: any future helper, extension or satellite bundle that
  presents its own UI must set it too, or it will go dark on a dark system.
- **Subtlety over skins**: the classic look lives in chrome, typography scale
  and the grid — not in texture overload. If a screen needs four kinds of
  bevel to feel classic, it's wrong; two is enough.

## Accessibility acceptance

Before a release ships, verify the home window, suggestion feed,
menu-bar companion (`MenuBarView`) and pane together on macOS:

- Keyboard-only: reach every action, open a suggestion, cancel confirmation
  and return to the originating control. Check focus after a feed refresh and
  pane switch; do not steal focus for new findings.
- VoiceOver: expose names, roles, selection, stale/unavailable state and action
  labels. Icons and badge colors are not the only carriers of meaning.
- Respect increased contrast, reduced transparency/motion and larger text
  while remaining light-only. Check wrapping and clipping at supported window
  sizes and display scales; fixed classic dimensions are not an exemption.
- Use native-semantic Rigi controls where available (`ClassicToolControl`,
  `ClassicToolbarButton`). Verify custom controls explicitly. The current
  `StatusBarView` includes zoom controls; the suite hides them rather than
  present inert buttons.

Add a macOS UI smoke flow for home → suggestion → pane → cancel/back, with a
fake observation/repair service. Check keyboard activation and accessible
labels. Record the VoiceOver/Full Keyboard Access pass and visual checks for
contrast, scaling and light appearance in the shipping module's PR.
Build success and a screenshot alone do not prove accessibility; Rigi's own
[verification guide](https://github.com/L-K-M/Rigi/blob/dcfc91e3b72aee612b2b48aed4a744397b78dc77/docs/verification.md)
makes the same distinction.

## Current visual checkpoint

The home window now has an inset tool grid, Rigi status bar, suggestion feed
and ten panes. Before release, capture the home and representative panes on
macOS and complete the keyboard, VoiceOver and visual checks above. The result
should be unmistakably "Norton, but polite".
