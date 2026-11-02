# Modules

Status of every candidate: what it does, where it comes from, what migration
costs, and what it could watch for. Order follows PLAN.md's phases.

Legend — **effort**: cheap (SwiftPM core moves nearly unchanged) · medium
(`.xcodeproj` port or not-yet-cloned) · port (non-Swift tech to re-implement).

## Confirmed roster

### DockVac — effort: cheap — phase 1 (first module)

Docker disk-usage treemap with selective reclaim — deliberately not a broad
`docker system prune`. Pure SwiftPM today.

- **Migrates:** its core (df parsing, treemap model, reclaim set) as
  `DockVacCore`; the treemap pane as its first real suite pane.
- **Watcher:** `docker system df` on a slow cadence → "Docker is holding ~X GB"
  at a configurable threshold. The proof-of-concept for the whole pipeline.
- **Privilege:** none to observe; the Docker socket only on the delete action.
- **UI:** AppKit throughout (`NSView`s, `NSToolbar`), no SwiftUI. The treemap
  pane needs an `NSViewRepresentable` host or a rewrite.

### RepoMen — effort: medium — phase 3

Finds developer caches and build artifacts — `target/`, `node_modules/`,
DerivedData, Homebrew caches — and reclaims them by age and size.

- **Migrates:** needs a `.xcodeproj` → SwiftPM port. The scan/ageing logic is
  the core; the review-and-delete UI becomes the pane.
- **Watcher:** periodic scan of configured roots → "N GB of build products
  older than 60 days".
- **Source facts:** Watch mode already scans user-added folders (none by
  default) every 6 hours, with a 30-day idle default. A scan walks up to 16
  levels and sizes every candidate, so it is not a cheap poll, and the default
  manual roots include `~/Documents`, which raises a Files & Folders prompt.
  RepoMen already has its own `MenuBarExtra`, login item and notifications.

### BootCaptain — effort: medium — phase 3

Inventories launch agents, login items and other startup mechanisms,
attributes them to installed products, and investigates boot failures. SwiftUI
app + CLI; **GitHub-only, not yet cloned**.

- **Migrates:** inventory/attribution core; its investigator UI as the pane.
  The CLI could survive as a bundled tool or stay in its repo.
- **Watcher:** diff the startup inventory on a cadence → "X installed 2 new
  login items". Boot-failure diagnosis stays an on-demand flow.
- **Source facts:** the shipping app and helper build from XcodeGen
  `project.yml`; `Package.swift` builds only the libraries and the CLI. Spawns
  live in `BootCaptainKit`, so the module needs Kit as well as Core. launchd
  plist folders are readable unprivileged, but Background Task Management
  (`sfltool dumpbtm`), the source for modern login items, needs root and
  likely Full Disk Access, and System Events login-item reads need Automation
  consent. An unprivileged watcher sees plists only.

### DeviceControlDoctor — effort: cheap — phase 2

Diagnoses Device Control / Data Access (TCC) permission records that look
granted but fail functionally. Already fleet-standard: `DoctorCore` is pure,
`ProcessRunner` is the only subprocess boundary, `tccutil`/`codesign` run via
fixed paths, repair is user-confirmed per service.

- **Migrates:** `DoctorCore` + the pane nearly unchanged — it is the model
  every other module's boundary copies.
- **Watcher:** periodic grant-vs-function drift checks where a cheap signal
  exists → "X lost its working permission after the update". No
  watcher-triggered resets, ever.
- **Source facts:** the cheap signal detects identity and record changes,
  not functional failure, so a suggestion can only say "verify again". Reads
  use `tccutil list`, verified only on macOS 27.2; elsewhere they degrade to
  unavailable. `ProcessRunner` is a concrete struct, so the reset path has no
  fake seam. The app inserts its `MenuBarExtra` unconditionally and monitors
  by default (`monitorEnabled = true`).

### Shortking — effort: medium — phase 3

Inventories system and app shortcuts, then uses live capture and diagnostic
tests to find who owns — or stole — a hotkey. **GitHub-only**.

- **Migrates:** the inventory/diagnosis core; capture stays in the pane.
- **Watcher:** inventory diff → "new shortcut conflict: ⌘⇧Space is claimed by
  two apps". Diagnosis itself is on-demand.
- **Source facts:** bundle id `com.shortking.app`. Needs Accessibility
  (menu shortcuts) and Input Monitoring (capture). `ShortkingKit` mixes AppKit,
  event taps, private SkyLight calls and process spawning; only its models,
  parsers and analysis are pure. Diagnosis writes system state: a blackout
  that disables every global hotkey for up to 30 s, and probe registrations
  run in a separate short-lived `shortking-probe` process that must stay
  separate. `ScanOptions.unprivileged` already scopes a watcher-sized scan,
  but a cold scan spawns hundreds of `nm` processes.

### HallPass — effort: cheap — phase 2

Manages system-wide CIDR exemptions from the macOS local-network privacy
restriction. Already fleet-standard: `HallPassCore` is pure; writes go through
privileged osascript with baseline re-check and rollback.

- **Migrates:** `HallPassCore` + pane. Its privileged write path is the case
  study for "per-module privilege stays per-module" — it keeps its own
  confirmation flow inside the suite.
- **Watcher:** little to offer; keep it on-demand. (Candidate: drift check —
  "your exemptions changed since you last saved".)
- **Source facts:** every UI string is German and hardcoded; every other
  module is English. The suite needs a language decision before this pane
  moves.

### Zen Backup Manager — effort: medium — phase 3

Inspects browser tabs and Spaces on a timeline of session backups; restores
with a verified safety copy and undo. **GitHub-only**.

- **Migrates:** the backup-timeline/restore core and its pane.
- **Watcher:** backup freshness → "last session snapshot is 9 days old".
- **Source facts:** Zen Browser only. Zen writes the session snapshots; the
  app reads them and writes safety copies around restores. A stale snapshot
  means Zen has not saved a session (unused, or crashing), not an overdue
  backup, so the suggestion must say that. Restore requires quitting Zen, and
  the pane offers to quit it.

### Obtainintosh — effort: port — phase 4

Tracks applications and fonts installed through GitHub/Forgejo releases and
compares them with what's installed. Currently Tauri — the logic is simple
(release feeds + version compare), so a native port is small.

- **Two shapes, decide at phase 4:** (a) a thin port of Obtainintosh as a
  pane; (b) the suite's generic updater — "apps installed from GitHub
  releases" regardless of fleet. Leaning (b): the suggestion "3 app updates
  available" is only useful with the whole picture, and it makes the suite
  the fleet's own update channel too.
- **Watcher:** this *is* the watcher — release-feed polling is its nature.

### RunningMan — effort: cheap — phase 2

Discovers self-hosted GitHub Actions and Forgejo runners in place, starts and
stops them, sets launch-at-login, registers new ones, follows job logs.
SwiftPM.

- **Migrates:** its discovery/control core + the manager pane.
- **Watcher:** runner health → "2 of 4 runners offline for 10 min — restart?"
- **Source facts:** discovery and control span `RunningManCore` and
  `RunningManServices`; the pane's drain engine, polling, notifications and
  widget publishing are about 7,200 lines in the app target. It has its own
  unconditional `MenuBarExtra`, login item, `runningman://` scheme and a
  WidgetKit extension that `scripts/build-app.sh` assembles from SwiftPM.
  Health states and 48 hours of activity samples exist; no
  offline-for-10-minutes rule does.

### Coreography — effort: medium — phase 3

The system monitor: CPU/memory/disk/network lanes, process table, menu-bar
extra, widgets, Shortcuts actions, a `coreo` CLI. `.xcodeproj` today.

- **Migrates:** the sampling/rendering core is the biggest port in the
  roster — worth it, because its samples feed half the watcher ideas. Its own
  menu-bar presence likely folds into the suite's (one menu face, many
  instruments).
- **Watcher:** sustained-pressure signals → "X has pinned a core for an hour";
  thermal/disk-full warnings.
- **Source facts:** the engine is already SwiftPM (`CoreographyKit`,
  `CoreographyServices`, `CoreographyDrivers`, plus the `coreo` and helper
  executables); Xcode builds only the app shell, widgets and packaging. Its
  menu-bar extra is the primary surface, not chrome. It keeps a one-hour
  in-memory history and SQLite rollups, and already ships its own alerts and
  notifications (memory, thermal, battery, disk). Unmentioned surfaces: App
  Intents, a `coreography://` scheme, a local MCP server (off by default) and
  "Ask", which sends system context to Anthropic or an OpenAI-compatible
  endpoint on request.

## Satellites — fleet tools that stay separate but can still feed suggestions

A satellite doesn't migrate; the suite can still watch *for* it or deep-link
out to it. These are deliberately not modules today:

| App | Why not a module | Relationship |
| --- | --- | --- |
| Lantenna (Tauri) | non-Swift stack | LAN-scan watcher idea: "new unknown host" — could become a native module later; the scan itself is small |
| Copywraith (Tauri/Rust) | clipboard manager, resident by nature | out of scope — its job isn't suggest-on-demand |
| Foldover (Rust engine) | file sync service | sync conflicts could surface as suggestions → its own app |
| Rememoru | window-layout recorder | restore-at-login is already resident; candidate if the suite wants a "layouts" pane |
| Sortomat | rule-based file sorter | strong future module — "Downloads is accumulating → sort now?" |
| LLimit + OpenCodeQuotaWidget + opencode-mystatus | three overlapping quota tools | consolidate among *themselves* first; then a "quota" module is an easy yes |
| Alan | active-window border | resident overlay, nothing to suggest |
| Eko | notification forwarder | cross-device app, different product |
| Gans, VaultSquire, MonkeysPaw, Vervellum | auth/secrets/text tools | security-adjacent or personal-data apps — keep their own trust boundaries out of the suite |
| TopDrawer, Invoque, Jetty, Zap | launchers/switchers | different product family entirely |

## New module ideas — things no fleet app does yet

Ordered by fit with the suite's job ("notice a problem, open the right tool"):

- **App uninstaller + leftover sweep** — the classic suite tool. Watcher:
  "app X was trashed; its support files remain". Privileged only on delete.
- **Duplicates finder** — Norton had one; users expect it. On-demand pane;
  watcher optional ("Downloads has 400 MB of dupes").
- **Secure erase / WipeInfo homage** — file shredder for sensitive files.
  Small, self-contained, very on-brand.
- **Whole-disk map** — DockVac and RepoMen cover Docker and dev caches; a
  general "what's eating my disk" treemap is the missing general case.
- **Backup freshness** — "Time Machine (or your backup tool) hasn't run in N
  days". Watcher-only; may not even need a pane beyond Settings.
- **Battery & storage health** — cycle counts, SSD wear where exposed, free
  space trend. Pane + gentle warnings.
- **System info pane** — the "About This Mac, but useful" tile: serial, OS,
  uptime, warranty-ish facts. Cheap, friendly, very Norton.
- **Network diagnostics** — Wi-Fi quality, DNS reachability, captive-portal
  check. Complements HallPass/Lantenna territory.
- **Hosts-file editor** — small, fits the network corner next to HallPass.
