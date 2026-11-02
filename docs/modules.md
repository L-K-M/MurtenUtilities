# Modules

Status of every candidate: what it does, where it comes from, what migration
costs, and what it could watch for. Order follows the home screen
(`ModuleRegistry.all`); each heading names the module's phase.

Legend — **effort**: cheap (SwiftPM core moves nearly unchanged) · medium
(`.xcodeproj` port or not-yet-cloned) · port (non-Swift tech to re-implement).

## Platform floors

The suite declares macOS 26 (`Package.swift`, `LSMinimumSystemVersion`;
PLAN.md, *Deployment floor*). The source repos declare these floors
(checked 2026-11-02 against each `main`):

| Module | Declared floor | Declared in | What needs it |
| --- | --- | --- | --- |
| DockVac | 13 | `Package.swift` | fits the suite |
| RepoMen | 13 | `.xcodeproj` | fits the suite |
| BootCaptain | 13 | `Package.swift`, `project.yml` | fits the suite |
| DeviceControlDoctor | 14 | `Package.swift` | fits the suite |
| Shortking | 14 | `Package.swift` | fits the suite |
| RunningMan | 14 | `Package.swift` | fits the suite |
| Zen Backup Manager | 14 | `.xcodeproj` | fits the suite |
| HallPass | 26 | `Package.swift` | The pane uses Tahoe-only SwiftUI (`ToolbarSpacer`). The feature needs 15.5: local network privacy arrived in macOS 15 and the exemption defaults in 15.5 (TN3179). |
| Coreography | 26 | `Package.swift`, `.xcodeproj` | A product decision in its own plan (`docs/plan.md`, decision 1), not an API gate: the tree has no `#available` checks. Its private NetworkStatistics keys are verified only "as the framework publishes them on macOS 26". |
| Obtainintosh | Tauri app | `tauri.conf.json` | a port; no Swift floor yet |

Every module's floor is at or below the suite's, so no module needs an
availability fallback or an OS applicability check, and CI (`macos-26`)
tests the only supported release.

## Confirmed roster

### DockVac — effort: cheap — phase 1 (first module)

Docker disk-usage treemap with selective reclaim — deliberately not a broad
`docker system prune`. Pure SwiftPM today.

- **Migrates:** `DockVacCore` (usage analysis, treemap model, reclaim set)
  plus the `DockVacDocker` Engine API transport the scan service wraps; the
  treemap pane as its first real suite pane.
- **Watcher:** a slow-cadence scan through an observation-only Docker Engine
  service → "Docker is holding ~X GB" at a configurable threshold. An endpoint
  requiring interactive authentication is unavailable to background polls.
  The proof-of-concept for the whole pipeline.
- **Capability:** scans and deletion both use the Docker Engine connection
  (Unix socket or SSH). A watcher gets a scan-only service interface, not the
  mutation client; the daemon connection itself is not a read-only grant.
- **UI:** AppKit throughout (`NSView`s, `NSToolbar`), no SwiftUI. The treemap
  pane needs an `NSViewRepresentable` host or a rewrite.

### RepoMen — effort: medium — phase 3

Finds developer caches and build artifacts — `target/`, `node_modules/`,
DerivedData, Homebrew caches — and reclaims them by age and size.

- **Migrates:** needs a `.xcodeproj` → SwiftPM port. The scan/ageing logic is
  the core; the review-and-delete UI becomes the pane.
- **Watcher:** periodic scan of configured roots → "N GB of build products
  older than 60 days".
- **Existing automation:** RepoMen's Watch mode can move stale artifacts to
  the Trash after every periodic check once the user arms it
  (`watchAutoTrash`, off by default; `RepoMen/Watch/WatchManager.swift`).
  That is a watcher with a write path, which the suite forbids, so it cannot
  migrate as a watcher. Whether it survives in another form is open
  (PLAN.md, *User-armed automation*).
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
- **Privilege:** ships a root helper today (`SMAppService.daemon`) whose
  enabled actions are reversible vault moves — launchd/cron mutations stay
  gated off in the current build — and the app itself is Developer ID
  signed, notarized and non-sandboxed. The helper embeds per-module at
  migration and gates on the signing decision (docs/architecture.md §
  Module packaging).
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
granted but fail functionally. `DoctorCore` is pure, `ProcessRunning` is the
only subprocess boundary, `tccutil`/`codesign` run via fixed paths, repair is
user-confirmed per service.

- **Status:** available. `DoctorCore` (in `Sources/DeviceControlDoctorCore`)
  and `DeviceControlDoctorModule`; the source's tests run as
  `DeviceControlDoctorCoreTests` and `DeviceControlDoctorIntegrationTests`.
- **Provenance:** DeviceControlDoctor@09accf844d6118bf0eea927ef4f6a8dd52fd033b
- **Pane:** the standalone main window. It checks when it appears and, while
  *Check every minute* is on (the default), every minute and after app
  launches and wake, only while visible. The Test Pad is a module window
  (`test-pad`); the File-menu commands are Tool-menu commands with the same
  shortcuts (⌘O, ⌘R, ⇧⌘E); the menu-bar extra is a companion section
  (watched apps, apps needing review, Refresh, Test Pad). Launch at login
  is the suite's.
- **Watcher:** every 30 minutes (120 s timeout, local), per watched app:
  `tccutil list` for its expected permissions and `codesign` against the
  identity the pane saved. One finding per app (scope: its watch-list id)
  when an expected permission reads denied or limited, the signing identity
  changed, or an earlier change has no passing test since → "Verify <App>'s
  permissions again", route `review` with context `app`. Unclear answers,
  timeouts and a missing `tccutil list` (macOS 26) are failures, never
  healthy. Apps in, or linked into, privacy-guarded places (Desktop,
  Documents, Downloads, iCloud Drive and file providers, other apps'
  containers, other volumes, any home folder but `~/Applications` and
  `~/Library`) are left to the pane. It never resets, writes or prompts.
- **Preselection:** the route selects the named app in the watch list and
  nothing else. The repair sheet opens only on the user's click, with the
  app's expected permissions checked, as in the standalone app.
- **State:** the watch list stays at
  `~/Library/Application Support/DeviceControlDoctor/watchlist.json`, read
  and written in place; `monitorEnabled` is in the module's defaults.
- **Coexistence:** the standalone app writes the same file, so the last save
  wins; the pane says so while the standalone app runs. App discovery skips
  the suite and the standalone app.
- **Source facts:** the cheap signal detects identity and record changes, not
  functional failure, so a suggestion can only say "verify again". Reads use
  `tccutil list`, which its AGENTS.md records as verified only on macOS 27.2;
  elsewhere they degrade to unavailable.

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

- **Migrates:** `HallPassCore` + pane. Its privileged write path keeps its
  own confirmation, baseline re-check and rollback inside the suite; this is
  a repair-flow boundary, not OS-enforced isolation from other modules.
- **Watcher:** keep it on-demand. The current read service also requests
  administrator access, so it cannot back a watcher. A future "exemptions
  changed" check needs an unprivileged signal first.
- **Source facts:** every UI string is German and hardcoded; every other
  module is English. The suite needs a language decision before this pane
  moves.

### Zen Backup Manager — effort: medium — phase 3

Inspects browser tabs and Spaces on a timeline of session backups; restores
with a verified safety copy and undo.

- **Status:** available. The `.xcodeproj` is ported to SwiftPM:
  `ZenBackupManagerCore` (session decoding, timeline, restore with safety
  copies, the rule) and `ZenBackupManagerModule` (pane, provider, watcher).
  The source's 23 tests moved to `ZenBackupManagerCoreTests`.
- **Provenance:** ZenBackupManager@14efe4434430e453b5a53e79434d2ea828ad70ba
- **Applicability:** a profile listed in Zen's `profiles.ini`; otherwise
  "Zen Browser is not installed".
- **Watcher:** hourly, unprivileged and metadata only: `profiles.ini`, then
  the dates of each profile's session files (current state,
  `zen-sessions-backup/`, `sessionstore-backups/`; never the safety copies).
  One finding per profile, scoped by its folder path. At 7 days or more:
  "Zen has not saved a session in N days", opening
  `murten://zenbackupmanager/timeline?profile=<path>`. A restore rewrites the
  current session file, so it counts as a save.
- **Preselection:** the profile only. The pane re-scans it and selects its
  current state, never a backup to restore; restoring still takes the
  confirmation sheet, which offers to quit Zen.
- **State:** safety copies stay in
  `~/Library/Application Support/ZenBackupManager/Safety Copies` and are read
  in place, so undo sees the standalone app's copies too. No preferences
  migrate: the standalone app's only ones belonged to its update checker,
  which is removed. Quitting during a restore asks first.
- **Coexistence:** both apps take Zen's profile lock while restoring, so a
  restore in one is refused while the other is writing.
- **Source facts:** Zen Browser only. Zen writes the session snapshots; the
  app reads them and writes safety copies around restores. A stale snapshot
  means Zen has not saved a session (unused, or crashing), not an overdue
  backup, so the suggestion must say that. Restore requires quitting Zen, and
  the pane offers to quit it.

### Obtainintosh — effort: port — phase 4

Tracks applications and fonts distributed through GitHub or Forgejo
releases, compares them with what is installed, downloads a matching asset
and reveals it in the file manager. It does not install or replace
anything. Tauri 2 and SvelteKit, shipped for macOS and Linux.

- **Size:** about 10,400 lines of Rust, 186 tests included, and 2,500 lines
  of TypeScript/Svelte. A native port re-implements all of it.
- **Scope is already generic:** users add any GitHub or Forgejo repository.
  The repo's `GENERIC_SOURCES.md` designs arbitrary vendor download pages
  behind an identity and SSRF contract. PLAN.md's open question is whether
  the suite keeps, narrows or extends that.
- **Installed-app identity** on macOS is the user-typed name matched
  against `<name>.app` in `/Applications` and `~/Applications`
  (`src-tauri/src/installer.rs`), not a bundle id. A count like "3 app
  updates available" inherits that guess; the repo's `ANALYSIS.md` already
  specifies bundle-id matching.
- **State:** `~/Library/Application Support/Obtainintosh/apps.json` holds
  the tracked list and GitHub and Forgejo tokens in plain text
  (`src-tauri/src/models.rs`). A migration imports the tokens into the
  Keychain instead of copying the file, and leaves the standalone app's copy
  alone while that app still runs.
- **Platforms:** a Swift port is macOS-only. Linux users (deb, AppImage,
  Flatpak) keep the Tauri app, so it stays maintained whatever the suite
  does.
- **Shapes, decide at phase 4:** (a) a pane that ports today's
  download-and-reveal flow; (b) the suite's updater, which also needs the
  verified install `ANALYSIS.md` specifies and does not exist yet (mount,
  bundle id, signature, signer continuity) before "update" means more than
  "download".
- **Watcher:** checks run at launch and on demand; nothing polls today. The
  suite's scheduler would supply the cadence. Checks use GitHub's REST API:
  60 requests an hour unauthenticated, 5,000 with a token.

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
  Health states and 48 hours of activity samples exist, but there is no
  offline-for-10-minutes rule yet.

### Coreography — effort: medium — phase 3

The system monitor: CPU/memory/disk/network lanes, process table, menu-bar
extra, widgets, Shortcuts actions, a `coreo` CLI. `.xcodeproj` today.

- **Migrates:** the sampling/rendering core is the biggest port in the
  roster — worth it, because its samples feed half the watcher ideas. Its own
  menu-bar presence likely folds into the suite's (one menu face, many
  instruments).
- **Privilege:** ships a root XPC sampling daemon today (counters, open
  files, sockets, signal/renice, spindump, BTM dump) that refuses to start
  under ad-hoc signing. It embeds per-module like BootCaptain's helper —
  same signing gate (docs/architecture.md § Module packaging).
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

## What a suggestion may preselect

A deep link can open a pane with a selection already made, and one click
then confirms it. The module owns that selection rule, not the suggestion
engine:

- The headline counts exactly what the preselected set frees. DockVac's
  "~8 GB" comes from its own analysis, not from the `RECLAIMABLE` column of
  `docker system df`, which also counts stopped containers, unused volumes
  and every unused image.
- Data-bearing or non-reproducible targets are never preselected. The user
  adds them in the pane, one by one, with the module's own warnings.
- A module whose dossier states no rule preselects nothing.

| Module | May preselect | Never preselects | Source |
| --- | --- | --- | --- |
| DockVac | Its *Rebuildable* level: untagged image leftovers and unused build cache (`AutomaticCleanupLevel.safe`) | Containers and volumes, which no DockVac level removes; *re-pullable* images, which the user opts into in the pane | `Sources/DockVacCore/AutomaticCleanup.swift`, README |
| RepoMen | Nothing: "Nothing is pre-selected; you check items" | Anything | README |
| Others | Nothing until their dossier states a rule | Anything | |

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
- **Deletion/privacy guidance, not a file shredder** — do not promise secure
  per-file erasure on SSDs or APFS. Overwriting a path cannot prove removal of
  old blocks, clones, snapshots or backup copies. Apple does not offer
  [Disk Utility secure erase for SSDs](https://support.apple.com/guide/disk-utility/erase-and-reformat-a-storage-device-dskutl14079/mac).
  A future pane could explain FileVault and supported whole-device erase
  workflows; it must distinguish deleting a file from sanitizing a device.
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
