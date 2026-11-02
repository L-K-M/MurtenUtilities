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
[docs/modules.md](modules.md). The contracts and data flow live in
[docs/architecture.md](architecture.md). The look lives in
[docs/ui-direction.md](ui-direction.md).

## Product shape

- **Home window** — the Norton grid: friendly icon, name, one-line
  description per tool. Each tool opens in the same window as its own pane.
- **Menu-bar companion** (opt-in) — watches quietly, collects suggestions,
  shows a badge count when there's something worth seeing. Launch at login via
  `SMAppService`, off until the user turns it on.
- **Suggestion feed** — on the home screen and in the menu. Every suggestion
  deep-links into the relevant pane with a safe default preselected. Example:
  the watcher sees ~8 GB of unused Docker images → "Docker is holding ~8 GB —
  clean up?" → opens DockVac with the reclaimable set selected. Nothing
  repairs without a click.

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
| DockVac | `DockVac` (SwiftPM) | Docker disk reclaim | `docker system df` growth → "clean up?" |
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
[docs/modules.md](modules.md).

## Phases

0. **Scaffolding** (done): package, home screen listing the registry, Rigi
   wired end-to-end, CI/CD/release plumbing, this plan.
1. **The spine**: `SuiteCore` contracts, the suggestion store
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
  `*Core`-style target plus its pane.
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
- **Obtainintosh scope.** Generic "anything installed from a GitHub/Forgejo
  release" updater, or just the fleet? Leaning generic — the suggestion is
  only useful with the full picture.
- **Name.** `MurtenUtilities` is the repo and bundle id; the *displayed* name
  can stay "Murten Utilities" or take a friendlier one later.
- **Signing.** Ad-hoc now; Developer ID + notarization later is a distribution
  question — and HallPass-class modules that write system preferences may
  shape the answer.
- **Suite icon language.** Tiles use SF Symbols today; real per-tool icons
  need a shared grammar (docs/ui-direction.md, Pict as the fleet's icon
  store).
