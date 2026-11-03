# Architecture

## Package layout

```
Sources/
  MurtenCore/         pure logic — no AppKit, no process spawning, no privilege
    SuiteModule         module descriptor (id, name, one-liner, icon, status) + ModuleRegistry
    Finding/WatchObservation what a watcher saw, per scope, including failures
    Watcher             observe() → WatchObservation; cadence, timeout, resources
    SuggestionRule      finding → at most one suggestion, with hysteresis
    SuggestionLedger    episodes, dedupe, snooze, dismissal, staleness, health
    SuggestionStore     the ledger's single owner; JSON persistence
    WatchSchedule/WatchCoordinator  cadence, back-off, gate, cancellation
    ModuleRoute         murten://module/action?context, allowlist-validated
    SuiteSettings       resident mode, per-module watchers and notifications, pauses
  MurtenModuleKit/    SuiteModuleProvider, ModuleContext, module windows and commands
  MurtenShell/        the app: AppModel, live services, scenes, views — a library,
                      so app-level tests run against fake services
  MurtenUtilities/    the executable: @main plus the module catalog
  <Tool>Core/         migrated pure logic per tool (DockVacCore, …) — one
                      target each, kept free of AppKit/spawn/privilege
  <Tool>Services/     the IO side a watcher needs when the source app has
                      one (DockVacDocker's Engine client, a runner front) —
                      library targets with injectable boundaries
  <Tool>Module/       each module's provider, pane and watcher
Tests/
  MurtenCoreTests/    contracts: registry, routes, ledger, store, schedule, coordinator
  MurtenShellTests/   AppModel against fake services and a fake module
  <Tool>CoreTests/    each migrated core keeps its existing suite
  <Tool>ModuleTests/  watcher logic against fixtures, never the live system
```

The contracts, abridged:

```swift
public protocol Watcher: Sendable {
    var moduleID: String { get }
    var cadence: WatchCadence { get }          // ≥ 15 min, timeout, .network
    func observe() async -> WatchObservation   // never throws; failures are data
}

public protocol SuggestionRule: Sendable {
    func suggestion(for finding: Finding, state: RuleState) -> SuggestionContent?
}

@MainActor public protocol SuiteModuleProvider: AnyObject {
    var moduleID: String { get }
    var routeActions: [String: Set<String>] { get }
    var watch: WatcherRegistration? { get }
    func applicability() async -> Applicability
    func makePane(route: ModuleRoute?) -> AnyView
    func makeSettings() -> AnyView?
    func makeWindow(_ request: ModuleWindowRequest) -> AnyView?
    var interruptionWarning: String? { get }
}
```

Watcher implementations live in the `<Tool>Services` or `<Tool>Module`
library, not in `MurtenCore` (which stays pure) and not in the app
executable: a SwiftPM test target cannot import an executable target, so
fixture-tested watchers must sit in importable libraries behind injectable
process/socket boundaries. DockVac's existing `DockVacDocker` +
`DockVacDockerTests` pair is the pattern to copy. The step-by-step guide is
[migrating-a-module.md](migrating-a-module.md).

## The suggestion pipeline

```
poll ──▶ finding ──▶ rule ──▶ suggestion ──▶ store ──▶ surfaces
(cheap, unprivileged)  (threshold)  (key, module,    (dedupe,    (home feed,
                                     title, detail)   snooze,     menu badge,
                                                      rate-limit) notification*)
                                                              * opt-in only

click suggestion ──▶ deep link ──▶ module pane ──▶ explicit confirm ──▶ repair
                                                 (safe default           (module's own
                                                  preselected)            privilege boundary)
```

- **Watchers** run on a cadence (per-module interval, coalesced). They must be
  cheap and must not require privilege *to look*. The canonical example is
  DockVac's watcher reusing the Engine API client it inherits from the
  standalone app: reading the local Docker socket needs no elevation, and
  DockVac never shells out to the `docker` CLI. A check that needs privilege
  is a tool action, not a watcher.
- **Findings** carry a condition, target identity, observation time and typed
  evidence. Identity includes scope: two Docker endpoints or runner installs
  must not share a key merely because both report the same condition. A poll
  can return multiple findings and must state which scopes completed.
- **Rules** turn findings into at most one suggestion per `key`. Thresholds
  ("≥ 4 GB reclaimable", "≥ 1 runner offline ≥ 10 min") live with the module.
  Use duration/hysteresis where values fluctuate; changing byte counts alone
  must not create a new suggestion or notification.
- **SuggestionStore** has one serialized owner. It dedupes by `key`, retains
  snoozes/dismissals across refreshes and restarts, and persists to
  `~/Library/Application Support/MurtenUtilities/suggestions.json`. Bound
  retention. Rate-limit notification delivery, not collection of findings.
- **Surfaces** show active suggestions and distinguish stale observations from
  current ones. Only per-category opt-in permits `UNUserNotification`.
  Refreshes and startup restoration never replay old notifications.
- **Routes** identify a module, an allowlisted action and typed context, not a
  command or an executable path: `murten://<moduleID>[/<action>][?key=value]`.
  The app registers no URL scheme; the notation round-trips through
  notification payloads and is validated against each module's allowlist on
  the way back in. External links stay out until decided separately.

### Observation and suggestion lifecycle

- A successful, complete observation can mark a condition active or resolved.
  A `WatchObservation` lists the scopes it completed and the failures it hit, so
  "checked and absent" (resolved), "not checked" (unchanged) and "check
  failed" (stale) stay distinct. A failed/incomplete check never proves a
  condition resolved.
- Record last success and failure separately. Permission denial, missing
  tools, offline endpoints, parse errors and timeouts make the check
  unavailable or its previous finding stale, not healthy. Show a non-modal
  diagnostic; retry with bounded backoff, without repeated setup prompts.
- Snoozing suppresses surfacing until its deadline; refreshes preserve it.
  Dismissal suppresses the current condition episode. A verified resolution
  followed by recurrence may create a new episode; ordinary value changes
  may not. Define expiry and material-change rules with each module.
- Clicking a suggestion only opens a pane. Re-scan and bind the selection to
  the current endpoint/resource identity before presenting confirmation.
  Changed, missing or newly in-use targets require a revised preview. A
  restored suggestion or external link never authorizes a repair.

### Poll ownership and opt-out

- One coordinator owns scheduling, with at most one in-flight poll per
  watcher. Coalesce wake events; bound concurrency, runtime and I/O per
  watcher. Cancellation must stop child work, not just stop awaiting it.
- Disabling a watcher or resident mode cancels background work and prevents
  late results from surfacing or notifying. Snoozing affects presentation,
  not consent to run checks. On-demand checks remain module actions.
- Define battery, network and sleep/wake budgets before enabling the first
  watcher. No polling merely because a view was constructed or a timer from
  a standalone app survived migration.

## Privilege and capability model

Per-module confirmation is a product boundary, not process isolation. Swift
package targets in one executable share its process and available capabilities;
a module name does not isolate TCC grants, file access, credentials or sockets.
Do not promise OS-enforced per-module permissions in the single-process shell.

- Watchers receive observation-only domain services, not repair services or
  raw command/socket clients. Pure cores describe findings and repair plans;
  application services own side effects; adapters own OS access.
- Observation never prompts for administrator access or a new privacy grant.
  If a capability is unavailable, report the check as unavailable. Offer setup
  in the module after the user opens it; do not silently treat it as healthy.
- Repair coordinators require explicit confirmation of the current target and
  operation. HallPass retains its baseline re-check and rollback;
  DeviceControlDoctor retains its scoped, confirmed `tccutil reset`.
- DockVac scans already use the Docker Engine API over a Unix socket or SSH.
  The connection can also authorize mutation; a read operation is not a
  read-only credential. Give the watcher only a scan interface, a guardrail
  against accidental writes, not process isolation. Never run cleanup through
  that interface or initiate authentication prompts from a background poll.
- HallPass currently authorizes both reads and writes through osascript.
  Its existing read service is therefore not a watcher. Any drift watcher
  needs a separate unprivileged signal, or remains on-demand.
- Before adding a permission-sensitive module, record its capabilities,
  requesting identity, prompts and background behavior. If OS-enforced
  isolation is required, design and verify a separate process/identity and a
  narrow interface first; moving code to another target is insufficient.
- Any privileged helper must have a module-specific interface and explicit
  write-time authorization. Use `SMAppService` where appropriate; never add a
  suite-wide root daemon or expose arbitrary command execution.

## Resident mode

- `MenuBarExtra` is the resident face; it does **not** launch at login by
  itself. Closing a window does not stop the process or its watchers.
- Resident mode defaults off. It inserts the menu extra and allows
  background checks; launch at login and notifications are separate
  settings. Removing the item from the menu bar turns resident mode off.
- Launch at login is an explicit Settings toggle →
  `SMAppService.mainApp.register()` / `.unregister()`.
- Watchers pause on battery, in Low Power Mode, during quiet hours and, for
  network checks, on metered networks (Settings › Background Checks; the
  first three default on, quiet hours off). Budgets: cadence ≥ 15 minutes,
  a per-cadence timeout (60 s default), at most two polls at once, failures
  back off up to 6 hours, overdue checks after wake run once after 60 s. A
  watcher still running at its timeout is reported as timed out and its
  slot freed; it is not polled again until that work ends.

## Module packaging

Chosen: **migrate code in.** Each tool's pure core becomes a `<Tool>Core`
target in this package (or merges into `MurtenCore` when tiny); its pane lives
in the app. The source repos are small and mostly single-purpose, so code
moves cleanly; the standalone apps keep working from their own history.

Two roster modules ship privileged helpers in their standalone apps (see
Privilege and capability model above): BootCaptain's root vault helper and
Coreography's peer-code-signature-checked sampling daemon. Both helpers are
left out of the current ad-hoc suite build, and their modules disable the
helper-backed actions. A future Developer ID build can embed one separately
signed helper per module under `Contents/Library/LaunchDaemons`; signing is a
distribution task, not a migration blocker.

Rejected for now: **depend on the tool repos as remote Swift packages.** It
preserves a single source of truth per core, but it couples the suite's build
to ten repos' cadences and pins the suite to each repo's release discipline.
Revisit only if the standalone apps stay alive long-term — at that point the
shared cores could be extracted into their own tiny packages both sides
consume.

Per-module update checks do not migrate. Four roster apps check for new
releases of themselves, on by default (RunningMan through a manifest file,
the others through the GitHub releases API):

| App | Checker | Announces with |
| --- | --- | --- |
| Coreography | `Sources/CoreographyServices/UpdateChecker.swift` | a notification |
| RunningMan | `Sources/RunningMan/AppUpdateChecker.swift` | an in-app banner |
| RepoMen | `RepoMen/Updates/UpdateChecker.swift` | a modal alert, from a background check |
| Zen Backup Manager | `ZenBackupManager/Updates/UpdateChecker.swift` | the same modal alert |

Inside the suite a module has no version of its own, so these checks would
announce standalone releases the suite cannot install, and three of them do
it through surfaces the suite rules out (a default-on notification, a modal).
The suite has one update check for its own bundle; whether it runs by default
is open (PLAN.md, *Suite updates*).

## Module applicability

`SuiteModule` says what a tool is, not whether it can run on this Mac. Its
`Status` is only `planned` or `available`. The provider's `applicability()`
answers the second question:

- **Minimum OS**: the suite declares macOS 26, at or above every module's
  floor (HallPass needs 15.5 for the exemption defaults it edits,
  [TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)),
  so no module is inapplicable for its OS today. A module that later needs a
  newer release checks it here.
- **Required environment**, checked cheaply and without a prompt: a Docker
  endpoint for DockVac, a Zen profile for Zen Backup Manager, installed
  runners for RunningMan.

An inapplicable module never runs its watcher, never surfaces a suggestion and
never opens a pane that cannot work. Showing it with the reason or hiding it
is a UI decision. Declared floors per module are in
[modules.md](modules.md#platform-floors).
## Transition from the standalone apps

Until PLAN.md's *Standalone app fate* is settled, each migrated tool exists
twice. Three rules hold either way:

- **Record provenance.** Each migrated core notes the upstream commit it was
  copied from (docs/modules.md). Without it, fixes made on either side after
  the move cannot be found and the copies drift unnoticed.
- **Never orphan undo data.** The suite's bundle id gives it its own
  UserDefaults domain. The paths below are hardcoded app names, so code moved
  verbatim shares them with the standalone app, and renaming them to
  `MurtenUtilities` hides what the standalone app saved. Some of that is the
  user's only way back:

  | Module | State | Holds |
  | --- | --- | --- |
  | BootCaptain | `~/Library/Application Support/BootCaptain/{Vault,Journal}`, `/Library/Application Support/BootCaptain/Vault` | startup items it moved aside; unfinished actions |
  | HallPass | `~/Library/Application Support/HallPass/{Backups,Draft.json}` | the backup taken before each apply; unsaved edits |
  | Zen Backup Manager | `~/Library/Application Support/ZenBackupManager/Safety Copies` | the copy taken before each restore |
  | RunningMan | Keychain items; launchd labels `ch.lkmc.RunningMan.forgejo.*` | Forgejo tokens; which runners it manages |

  A module reads these locations, or imports them once with the user's
  consent; it never starts empty over them. Keychain items whose access list
  names the standalone app may prompt or fail when the suite reads them;
  verify per item before relying on a silent import.
- **Define coexistence.** With both installed, both copies can act on the same
  runners, startup items, preferences and the shared files above, and
  menu-bar items, login items and update checks double up. Each module states
  whether it defers to a running standalone app, and what the user sees.

## Testing strategy

- `MurtenCore`: registry invariants, dedupe/snooze/threshold rules, deep-link
  parsing — pure and fully unit-testable.
- Each `<Tool>Core` keeps the test suite it brings with it.
- `MurtenShellTests` drives `AppModel` with fake services and a fake module:
  opt-in, home/suggestion/pane routing, route validation, snooze/dismiss,
  notification opt-in, the quit guard, and a hosted render of `RootView`.
  Keyboard, VoiceOver, contrast and text-size acceptance live in
  [UI direction](ui-direction.md#accessibility-acceptance);
  unit tests and screenshots do not substitute for these checks.
- Watcher behaviour is tested against fixture command output, never the real
  system (same boundary discipline as DeviceControlDoctor's `ProcessRunner`).
  Fake clocks and services cover threshold oscillation, multiple targets,
  snooze/restart, resolution/recurrence, partial/failing observations, timeout,
  wake coalescing, opt-out during a poll, late results and stale deep links.
- Repair paths keep the automated tests they bring. The standalone apps
  already test repair plans, request validation, journals, recovery and
  deletes against fakes: HallPass `PreferencePlanTests` and
  `HallPassModelTests`, BootCaptain `RequestValidatorTests`,
  `MutationPolicyTests` and `FileJournalTests`, DockVac `FakeDaemonTests`,
  DeviceControlDoctor `RepairPlanTests`. Only the live authorization prompt
  and the real system write stay manual, and stay documented as such.
- The suite's own path from a suggestion to a repair (deep link, confirm,
  module action) gets fake-backed tests for denied authorization, cancel,
  system state that changed between preview and write, and partial failure.
