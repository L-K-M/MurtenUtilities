# Murten Utilities — plan

## What this is

One friendly Mac toolbox in the spirit of Norton Utilities for System 7 and
Mac OS 8: a home screen of small focused tools, plus an opt-in resident
companion that notices when a tool would help and offers to take you there.

It is **not** a monolith. Each tool keeps its own pane, its own pure-logic
module, and its own privilege surface. The suite contributes three things the
standalone apps can't: one place to discover the tools, one shared look, and
one suggestion pipeline that connects "something is worth your attention" to
the tool that fixes it.

The confirmed roster — and what each tool is for — lives in
[docs/modules.md](docs/modules.md). The contracts and data flow live in
[docs/architecture.md](docs/architecture.md). The look lives in
[docs/ui-direction.md](docs/ui-direction.md).

## Product shape

- **Home window** — the Norton grid: friendly icon, name, one-line
  description per tool. Each tool opens in the same window as its own pane.
- **Menu-bar companion** (opt-in) — watches quietly, collects suggestions,
  shows a badge count when there's something worth seeing. Launch at login via
  `SMAppService`, off until the user turns it on.
- **Suggestion feed** — on the home screen and in the menu. Every suggestion
  deep-links into the relevant pane with a safe default preselected. Example:
  the watcher sees ~8 GB of untagged image leftovers and unused build cache →
  "Docker is holding ~8 GB you can rebuild. Clean up?" → opens DockVac with
  exactly that set selected. The module defines what "safe" means
  (docs/modules.md, *What a suggestion may preselect*). Nothing repairs
  without a click.

## Principles

- **Opt-in, never nagware.** Resident mode is off by default; notifications
  are per-category and off by default; suggestions dedupe by finding, respect
  snoozes, and never go modal. When in doubt, quieter is correct — this is the
  line between a helpful companion and CleanMyMac's reputation.
- **Detection is not repair.** A watcher observes without privilege; a repair
  asks at its own write time, exactly as the standalone app does today.
- **Small tools, one job each.** The Norton model: a module does one thing,
  explains it in one line, and stays out of the way.
- **Classic look, modern manners.** Rigi chrome for the System 7/Mac OS 8
  feel; SwiftUI panes; proper accessibility, keyboard navigation, and dark
  appearance decisions rather than 1997's defaults.

## Confirmed roster

| Module | From repo | One-line job | Watcher → suggestion |
| --- | --- | --- | --- |
| DockVac | `DockVac` (SwiftPM) | Docker disk reclaim | Engine API disk-usage growth → "clean up?" |
| RepoMen | `RepoMen` (.xcodeproj) | dev caches & build artifacts | cache growth → "12 GB of build products" |
| BootCaptain | `BootCaptain` (Swift, GitHub-only) | startup items & boot failures | new/changed login items → "review what X added" |
| DeviceControlDoctor | `DeviceControlDoctor` (SwiftPM) | TCC permission diagnostics | grant-vs-function drift → "re-check X" |
| Shortking | `Shortking` (Swift, GitHub-only) | shortcut inventory & diagnosis | new conflict → "X stole ⌘⇧Space" |
| HallPass | `HallPass` (SwiftPM) | local-network CIDR exemptions | mostly on-demand |
| Zen Backup Manager | `ZenBackupManager` (Swift, GitHub-only) | browser-session backups | backup staleness → "last snapshot 9 days ago" |
| Obtainintosh | `Obtainintosh` (Tauri — port or rethink) | release-tracking updater | "3 app updates available" |
| RunningMan | `RunningMan` (SwiftPM) | self-hosted CI runners | runner offline → "restart?" |
| Coreography | `Coreography` (SwiftPM+.xcodeproj) | system monitor | sustained pressure → "X has pinned a core for an hour" |

Per-module migration notes, satellites, and new-module ideas:
[docs/modules.md](docs/modules.md).

## Phases

0. **Scaffolding** (done): package, home screen listing the registry, Rigi
   wired end-to-end, CI/CD/release plumbing, this plan.
1. **The spine**: `MurtenCore` contracts, the suggestion store
   (dedupe/snooze/thresholds), the deep-link router, the Settings section
   for launch at login and watcher pauses (docs/architecture.md §Resident
   mode wants it before the first watcher ships), and **one module
   end-to-end** — DockVac is the easiest proof (pure SwiftPM, cheap watcher).
2. **SwiftPM migrations**: HallPass, DeviceControlDoctor, RunningMan — their
   `*Core` targets move in nearly unchanged.
3. **Ports**: RepoMen and Coreography (`.xcodeproj` → SwiftPM cores);
   clone-and-migrate the GitHub-only apps (BootCaptain, Shortking,
   ZenBackupManager).
4. **Obtainintosh** as the updater module. Its scope, fleet only or any
   GitHub/Forgejo release, is still open (see Open questions).
5. **Satellites & new modules** — deferred fleet candidates and greenfield
   tools from the ideas list.

## Decisions so far

- **One app, two faces**: `WindowGroup` + `MenuBarExtra` in a single
  `@main App` — the pattern DeviceControlDoctor already ships.
- **SwiftUI panes + Rigi chrome** rather than osmium-ui/WKWebView. Rigi is
  native, already AppKit-classic, and proven in Lucerne and Sion; osmium-ui
  stays the reference if a web surface is ever wanted. See
  docs/ui-direction.md.
- **SwiftPM only** — no `.xcodeproj`; every tool contributes a pure
  `*Core`-style target plus its pane. SwiftPM has no app, extension or XPC
  product type, so `scripts/build-app.sh` assembles every bundle part by hand,
  as RunningMan's script already does for its widget extension and
  Shortking's for its probe executable. Two things it cannot produce: App
  Intents metadata, which only the Xcode build extracts
  ([Apple DTS](https://developer.apple.com/forums/thread/759160)), and
  compiled asset catalogs. Coreography's Shortcuts actions depend on the
  first, so they stay out of the suite or this decision gains an exception.
- **Migrate code in**, don't depend on the tool repos as packages. The suite
  becomes the home of each core; standalone apps keep working from their own
  history. Revisit if standalones stay alive long-term (docs/architecture.md
  §packaging).
- **Launchers stay out.** TopDrawer, Invoque, Jetty, Zap are a different
  product family ("get to your stuff faster") and a separate consolidation
  conversation.
- **Tauri/Rust tools stay satellites** initially (Lantenna, Copywraith,
  Foldover) — a satellite can still feed suggestions; embedding is a port.
- **Light appearance only — no dark mode.** The classic look *is* light
  platinum; a dark variant would be a redesign, not a reskin, and it's not
  worth paying now. Enforced app-wide via
  `NSRequiresAquaSystemAppearance` in `Info.plist`. If this ever changes it is
  a deliberate product decision plus real Rigi theming work — never a gradual
  accumulation of dark patches (docs/ui-direction.md).

## Open questions

- **Standalone app fate.** Keep shipping each tool alongside the suite, or
  does the suite become the product? Recommendation: keep them until the
  suite reaches per-module parity, then decide per tool.
- **Obtainintosh scope.** Obtainintosh is already generic: any GitHub or
  Forgejo repository the user adds. Keep that, narrow it to the fleet, or
  add vendor pages (its `GENERIC_SOURCES.md`)? Leaning generic — the
  suggestion is only useful with the full picture. Either way it downloads
  and reveals; it does not install (docs/modules.md).
- **Deployment floor.** The suite declares macOS 14; HallPass and Coreography
  declare macOS 26 (docs/modules.md, *Platform floors*). Raising the suite to
  26 means one tested OS, matching CI and both modules, but drops users of 14
  and 15 whom the other eight modules support. Keeping 14 widens reach, but
  HallPass's pane needs availability fallbacks and Coreography would sample
  on releases it was never verified on, neither covered by CI. A middle
  floor such as 15.5 is HallPass's own feature
  floor. Decide before Phase 2 migrates HallPass. Any floor still needs
  per-module applicability (docs/architecture.md).
- **Suite updates.** One update check for the suite bundle replaces the
  modules' own (docs/architecture.md §Module packaging). On by default keeps
  ad-hoc-signed installs current, but contacts GitHub without the user
  opting in; off by default matches "opt-in, never nagware" and leaves
  installs stale. Sparkle would be a second dependency. A fleet-scoped
  Obtainintosh could own this check.
- **Name.** `MurtenUtilities` is the repo and bundle id; the *displayed* name
  can stay "Murten Utilities" or take a friendlier one later.
- **Signing.** Ad-hoc now. That limits function, not just distribution.
  Privacy grants and Keychain item access are checked against the app's
  designated requirement, and an ad-hoc signature has no stable one: it is
  tied to that build ([TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)).
  Each update therefore loses Accessibility, Input Monitoring, Automation,
  Full Disk Access and folder grants, and Keychain items prompt again.
  RunningMan already works around both (`Sources/RunningManCore/Discovery.swift`,
  `Sources/RunningManServices/ForgejoConnectionStore.swift`). Shortking
  (Accessibility, Input Monitoring), BootCaptain (Automation, Full Disk Access
  for login items) and RepoMen (Documents, Full Disk Access for snapshots)
  need a stable identity, Apple Development or Developer ID, before they
  migrate; BootCaptain's and Coreography's helpers pin a Team ID as well.
  Pick the final identity early: switching between them changes the
  requirement, so users grant everything once more. HallPass does not drive
  this; its admin prompt is not a TCC grant.
- **Suite icon language.** Tiles use SF Symbols today; real per-tool icons
  need a shared grammar (docs/ui-direction.md, Pict as the fleet's icon
  store).
- **User-armed automation.** RepoMen's Watch mode, once armed, trashes stale
  artifacts after each check with no per-item click. That is a watcher with
  a write path, which the suite forbids (docs/modules.md, RepoMen). By
  contrast, RunningMan's stop-after-job is one click on a named runner,
  carried out later, and fits the rule. Dropping RepoMen-style automation
  keeps "nothing repairs without a click" absolute, but RepoMen users lose a
  feature. Allowing it only when armed per target, reversible, off by
  default and visible in the menu keeps the feature, but the rule gets an
  exception. Decide before RepoMen migrates in Phase 3.
