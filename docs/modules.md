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
`docker system prune`.

- **Status:** available. `DockVacCore` and `DockVacDocker` moved in unchanged
  with their tests and fixtures (Swift 6 mode); the AppKit app is
  `DockVacModule`. The driver tests' fake daemon and SSH bridge live in
  `Tests/DockVacDockerTests/Scripts`.
- **Provenance:** DockVac@a8fed1d880c5a16faba197fd741fc5f83cc9b328 (release
  1.5.0, the source repository's `main`)
- **Pane:** the standalone views, hosted through
  `NSViewControllerRepresentable`. The window toolbar and subtitle became a
  Rigi bar in the pane, the menu bar became Tool menu commands with the same
  shortcuts, sheets attach to the suite window, and the quit alert became
  `interruptionWarning`. The first scan runs when the pane first opens.
- **Watcher:** hourly, three minutes per poll. It reads containers, images
  and build cache (not volumes: no cleanup level removes one, and sizing them
  is the slowest read) from the endpoint DockVac's automatic search finds,
  through a reader with no removal. One finding per endpoint address,
  `reclaimable`, whose bytes are the safe level's plan. The rule opens at
  4 GB and holds until below 3 GB: "Docker is holding ~8 GB you can
  rebuild". An SSH endpoint (`DOCKER_HOST` or the active context) is skipped
  by default and reported unavailable, so its suggestion turns stale: an SSH
  agent such as 1Password or Secretive can prompt even under `BatchMode`.
  DockVac's Settings tab has "Check SSH endpoints in the background", off by
  default; with it on, the watcher connects with `BatchMode` and declares
  network use.
- **Route:** `murten://dockvac/reclaim?endpoint=<address>` re-scans that
  endpoint and, only if the scan reached it, replaces the selection with the
  safe level. The confirmation sheet is unchanged, its acknowledgement box
  off.
- **Applicability:** a socket in a known location, `DOCKER_HOST` or a Docker
  context; otherwise "No Docker endpoint found".
- **Capability:** scans and deletion both use the Docker Engine connection
  (Unix socket or SSH). The watcher's reader is a guardrail against
  accidental writes, not a read-only grant.
- **Coexistence:** DockVac keeps no files, so nothing is shared but the
  daemon. The standalone app and the module can both remove from it; every
  removal is non-forcing, and the other copy's next scan shows the result.
- **Left out:** `DOCKVAC_SMOKE_SCRIPT`, the window's saved frame, and the
  menu's checkmarks on Show Everything / Show Reclaimable Only (the bar's
  segmented control shows the filter).

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
attributes them to installed products, and investigates boot failures.

- **Status:** available.
- **Provenance:** BootCaptain@1fd84a9f6ec8626fa7ef8a5a100554944a733940
- **Migrated:** `BootCaptainCore` and `BootCaptainKit` with their test
  suites; the app's views, view model and services as `BootCaptainModule`.
  The `bootcaptain` CLI stays in its repo. Rescan (⌘R) and Run Boot Audit
  (⇧⌘R) are in the Tool menu; the pane scans when it appears, as the app
  did.
- **Privilege:** the root helper (`SMAppService.daemon`, bundle ID and
  Team ID pinned both ways) is left out, because ad-hoc suite builds cannot
  authenticate it. Moving `/Library` items to the root vault, and the
  launchd/cron toggles the standalone build already gates off, stay visible
  but disabled: "Needs a signed build of Murten Utilities". User-scope vault
  moves and login-item removal keep working, with their session undo. The
  helper embeds per module once the suite is signed (docs/architecture.md §
  Module packaging).
- **State:** Clean Up's vault and journal stay in
  `~/Library/Application Support/BootCaptain/{Vault,Journal}`. Items the
  standalone helper moved to `/Library/Application Support/BootCaptain/Vault`
  can only be restored by the standalone app. Undo history is per session,
  as before. The reviewed inventory is the module default
  `reviewedStartupInventory`.
- **Consent:** login-item reads and removals through System Events
  (Automation; `NSAppleEventsUsageDescription`), the Full Disk Access probe
  and Background Task Management (`sfltool dumpbtm` needs root, so the scan
  reports a coverage gap) stay in the pane's on-demand scan.
- **Watcher:** hourly, unprivileged read of `/Library/LaunchDaemons`,
  `/Library/LaunchAgents`, `~/Library/LaunchAgents` and the launchd plists
  apps embed (`/Applications`, `/Applications/Setapp`, `~/Applications`),
  compared with the inventory the user last reviewed in the pane → one
  suggestion per product, "Docker installed 2 new startup items", route
  `review`. The pane's first completed scan becomes the reviewed inventory;
  its review bar marks the current list as reviewed. Not watched: Apple's
  folders and `com.apple.` labels, BTM, login items, other users' homes.
  Without a reviewed inventory the check is unavailable; an unreadable
  folder makes it partial, so a suggestion goes stale instead of resolving.
- **Preselection:** none. `review` opens the "New since last review" filter
  with nothing selected; Clean Up preselects nothing, as before.
- **Source facts:** the standalone app and helper build from XcodeGen
  `project.yml`; `Package.swift` builds only the libraries and the CLI.
  Spawns live in `BootCaptainKit`, so the module needs Kit as well as Core.
  The app is Developer ID signed, notarized and non-sandboxed.

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

- **Status:** available. `HallPassCore` and its Swift Testing suites moved
  in unchanged apart from English messages; the app target became
  `HallPassModule` (provider, pane, backup store, privileged service), and
  its model tests moved to `HallPassModuleTests`. All keep the source's
  Swift 6 language mode.
- **Provenance:** HallPass@1ab2ac48ba98bc11d606e509cdedc88a3f8afa70
- **Migrated:** the Tahoe pane (sidebar, searchable table, inspector,
  editing and review sheets, Help), preview with sample data, named undo,
  draft recovery and the backup commands. The privileged write path keeps
  its own confirmation, baseline re-check and rollback inside the suite;
  this is a repair-flow boundary, not OS-enforced isolation from other
  modules.
- **Changed for the suite:** the UI and every message are English
  ("WLAN" is "Wi-Fi"). The app delegate, the window takeover and its
  close and quit guards are gone: the provider's `interruptionWarning`
  covers an unsaved draft, a load and an apply. The menu commands are
  Tool menu commands with the same shortcuts; window, full-screen and
  sidebar commands are the shell's. The `--demo` flag is gone; *Try with
  Sample Data* remains. The welcome shows the `ticket.fill` symbol
  instead of the application icon. Undo uses the window's undo manager
  while the pane is shown and leaves with it; it is not disabled during a
  load or an apply, which needed the window delegate. osascript waits on
  a dispatch thread rather than the shared cooperative pool.
- **State:** `~/Library/Application Support/HallPass/Backups` and
  `Draft.json` stay where they are, shared with the standalone app, so a
  draft from one appears in the other; the apply still re-checks the
  system state first. Quitting the suite keeps a real draft for next
  time. The restart reminder's keys (`restartRequiredAtUptime`,
  `restartRequiredBootTime`) live in the module's defaults, so a restart
  the standalone app asked for is not shown here.
- **Watcher:** none; HallPass stays on-demand. The read service requests
  administrator access, so it cannot back a watcher. A future "exemptions
  changed" check needs an unprivileged signal first.
- **Preselection:** nothing. The provider declares no route actions, so
  only the bare route opens the pane.

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
and reveals it in Finder. It does not install or replace anything.

- **Status:** migrated as a native port of the Tauri 2 and SvelteKit app:
  `ObtainintoshCore` (models, the `apps.json` and `.obtainintosh` formats,
  asset filters and the macOS asset picker, release selection, font version
  reading, version comparison, the Add Program form, the watcher's rule),
  `ObtainintoshServices` (GitHub and Forgejo REST clients behind an
  injectable transport, installed-version detection for apps and fonts, the
  tracked list, the Keychain vault, downloads, the watcher) and
  `ObtainintoshModule` (the pane and provider). The Rust and Svelte tests
  moved along as XCTest cases; the Linux-only parts (dpkg and AppImage
  detection, the Linux asset picker) stayed behind with their tests.
- **Provenance:** Obtainintosh@108a6c3e6bacb5485c87f490b1f3cc1d95651878
- **Scope stays generic:** any GitHub or Forgejo repository the user adds.
- **Installed-app identity:** the typed name matched against `<name>.app`
  in `/Applications` and `~/Applications`, as before; an entry may also
  record a bundle identifier, which is preferred when set.
- **State:** the suite keeps its own list at
  `~/Library/Application Support/MurtenUtilities/Obtainintosh/apps.json`
  (the standalone shape, without secrets). Tokens live in the Keychain
  (service `ch.lkmc.MurtenUtilities.obtainintosh`). When the standalone
  app's `~/Library/Application Support/Obtainintosh/apps.json` exists, the
  pane offers a one-click import, never automatic; that file is only read.
  Downloads share the standalone app's `$TMPDIR/obtainintosh-downloads`.
- **Watcher:** every 6 hours (`.network`), for each installed tracked
  program, is a newer release out? One finding per program, scoped by its
  entry id; the rule suggests when the latest version is newer, with the
  pane's comparison. Programs that are not installed cost no request.
  A poll spends at most 20 GitHub API requests without a token and keeps
  10 of GitHub's hourly 60 in reserve. Tokens come only from memory the
  pane already filled, so the check never reads the Keychain; a private
  Forgejo program whose key is not in memory is reported as not checked.
  Removed programs are reported as checked, so their suggestions resolve.
  A check in the pane, or removing a program, asks the suite to poll soon.
- **Preselection:** none. The suggestion's route `updates` opens the pane,
  which checks again; downloading stays a click.
- **Platforms:** macOS only. Linux users (deb, AppImage, Flatpak) keep the
  Tauri app.

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

### Coreography — effort: medium — phase 3 — migrated

The system monitor: CPU/memory/disk/network lanes, process table, menu-bar
extra, widgets, Shortcuts actions, a `coreo` CLI. `.xcodeproj` today.

- **Status:** available. The pane is the monitor window: a sidebar of
  sections (Overview cards, CPU, Memory, GPU, Storage, Network, Power &
  Thermals, Processes, Timeline, Startup, Recordings), with lanes, the
  process table, inspector, connections, sensors, the startup volume's
  space lens, Ask and the command palette. The menu section is its
  menu-bar extra (CPU, memory, network and disk mini lanes, the top
  process, pause, hold, HUD). Settings has a Coreography tab.
- **Provenance:** Coreography@f9820e66467e0991d2130a9d4d0c7ea6b00e3b8b
- **Targets:** `CoreographySystem` (C), `CoreographySQLite` (the source's
  `CSQLite`, renamed because target names are package-wide),
  `CoreographyDrivers`, `CoreographyKit`, `CoreographyServices` with their
  test suites; `CoreographyCore` (watcher, rule); `CoreographyModule`
  (provider, pane, menu section, settings). All Swift 6, as in the source.
  The C bridge contract tests moved to `scripts/coreography-bridge-tests/`
  (`run.sh`); `swift test` does not run them.
- **Sampling:** one model serves every surface, as in the standalone app,
  but it samples only while the pane or the menu section shows, the HUD is
  up, a recording runs or an MCP client is connected. History (the same
  SQLite rollups, `~/Library/Application Support/Coreography/History`)
  therefore covers the time Coreography was in use, not the whole session.
  Its alert rules still tint lanes while it samples; they no longer notify.
- **Watcher:** every 15 minutes, unprivileged, local (no `.network`), behind
  `SystemObserving`. Four checks, each its own scope: `processes` (a process
  averaging ≥ 0.8 of a core over the last hour, from CPU-time deltas between
  polls kept in memory; stays open while ≥ 0.5), `memory` (critical pressure
  at two checks in a row; stays open while warning or worse), `thermal`
  (heavy pressure at two checks in a row; stays open while moderate or
  worse), `startup-volume` (under 10 % free; clears at 12 %). It reads only
  the person's own processes: other users' need the helper. The process
  name sits in the condition (`sustained-cpu:<name>`) under the single
  `processes` scope, so an exited process resolves at the next complete
  check, and nothing resolves before the watcher has measured a full hour.
  The standalone battery alert stays out: macOS warns itself and watchers
  pause on battery by default.
- **Preselection:** nothing. Routes only navigate: `process?name=` opens
  Processes filtered by name and sorted by CPU; `memory` and `storage` open
  their sections with the process table by memory or disk writes;
  `thermal` opens Power & Thermals with the sensors. No row is selected, no
  action is armed and no space survey starts; quitting or signalling a
  process keeps its own confirmation.
- **Privilege:** the root XPC helper is Team-ID pinned, so ad-hoc suite
  builds leave it out (not embedded). Features behind it (other users'
  processes, spindump, raising priority, login and background items) show
  "Needs a signed build"; Settings shows the helper as unavailable.
- **Left out:** the helper; the widgets, their refresh and the briefing
  writer that feeds them; App Intents (SwiftPM cannot extract their
  metadata); the `coreo` CLI; the self update checker; the background
  mode, its login item and Dock presence, and the menu's Settings and Quit
  buttons (the suite's resident mode, login item and companion cover
  them); the Dock tile graph and the menu-bar title items (the shell owns
  the Dock and the status item); `coreography://` links and opening
  `.coreotrace` from Finder (the suite registers no URL scheme or document
  type; Open Recording… in the Tool menu reads them).
- **State:** preferences use the module's store under their old keys, so
  the standalone app's settings do not carry over. History, sessions
  (`…/Coreography/Sessions`), the MCP socket (`…/Coreography/mcp.sock`) and
  the Keychain items (`ch.lkmc.Coreography.provider`) keep their places.
  Whether an Ask key exists is read from Keychain attributes, so opening
  the pane does not prompt; using a key the standalone app saved may.
  The space lens walks only folders that never prompt until the person
  asks it to include Desktop, Documents, Downloads, app data and cloud
  drives; that choice (`spaceAccess`) is kept in the module's store.
- **MCP and Ask:** kept, off by default and on request as before. The suite
  does not ship `coreo`; clients use the standalone app's
  `Coreography.app/Contents/Helpers/coreo mcp --stdio`, which the client
  resolver treats as the bridge, so approvals still name the app behind it.
  An approval request opens the pane; with the window closed it times out.
- **Coexistence:** with the standalone app running too, both write the same
  history store and only the first to listen gets the MCP socket.

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
