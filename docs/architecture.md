# Architecture

## Package layout

```
Sources/
  MurtenCore/         pure logic — no AppKit, no process spawning, no privilege
    SuiteModule.swift   module descriptor (id, name, one-liner, icon, status)
    ModuleRegistry      the roster, in home-screen order
    Suggestion.swift    suggestion model + Watcher protocol
    (later)             SuggestionStore, snooze/threshold rules, Finding types
  MurtenUtilities/    the app shell
    MurtenUtilitiesApp  WindowGroup("home") + MenuBarExtra — the two faces
    HomeView            the Norton grid + suggestion feed
    MenuBarView         menu face: suggestions, watcher toggles, open/quit
    StatusBar           NSViewRepresentable → RigiUI
    (later)             DeepLinkRouter, per-module pane hosts, Settings
  <Tool>Core/         migrated pure logic per tool (DockVacCore, …) — one
                      target each, kept free of AppKit/spawn/privilege
  <Tool>Pane or in-app  each module's SwiftUI pane
Tests/
  MurtenCoreTests/    contracts: registry invariants, dedupe/snooze rules
  <Tool>CoreTests/    each migrated core keeps its existing suite
```

Current v0.1 scaffold contracts (not yet the full pipeline):

```swift
public protocol Watcher: Sendable {
    var moduleID: String { get }
    func poll() async throws -> Suggestion?   // cheap, unprivileged, nil = quiet
}
```

```swift
public struct Suggestion: Identifiable, Equatable, Sendable {
    public let key: String       // "<module>.<finding>" — dedupe identity
    public let moduleID: String  // deep-link target
    public let title: String
    public let detail: String
}
```

The scaffold's `poll() -> Suggestion?` skips the finding/rule boundary and
returns at most one result. Phase 1 must separate observation from rules and
support multiple findings before module watchers depend on this API. The
following lifecycle is the acceptance contract, not implemented behavior.

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
  command or an executable path. `murten://<moduleID>[/<action>]` is proposed
  notation; the scaffold has neither a URL handler nor scheme registration.
  Internal navigation does not require an externally registered URL scheme.
  Decide external-link support separately and validate all supplied context.

### Observation and suggestion lifecycle

- A successful, complete observation can mark a condition active or resolved.
  `nil` in the scaffold only means "nothing worth reporting"; it cannot also
  encode unavailable, partial, stale or resolved state. Define those outcomes
  in Phase 1. A failed/incomplete check never proves a condition resolved.
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
- The scaffold inserts the menu extra unconditionally and has no resident
  preference yet. Before watchers ship, resident mode must default off and
  govern background work independently of launch-at-login and notifications.
- Launch at login is an explicit Settings toggle →
  `SMAppService.mainApp.register()` / `.unregister()`.
- Watchers pause sensibly (on battery? metered network? user "quiet hours"?) —
  a Settings section, designed before the first watcher ships.

## Module packaging

Chosen: **migrate code in.** Each tool's pure core becomes a `<Tool>Core`
target in this package (or merges into `MurtenCore` when tiny); its pane lives
in the app. The source repos are small and mostly single-purpose, so code
moves cleanly; the standalone apps keep working from their own history.

Two roster modules already ship privileged launch-daemon helpers (see
Privilege model above): BootCaptain's root helper — reversible vault moves
enabled, launchd/cron mutations gated off in the current build — and
Coreography's root, peer-code-signature-checked sampling daemon (process
counters of other users' processes, open files, sockets, signals, renice,
spindump, the Background Task Management dump). Migrating those modules
embeds each helper in the suite bundle — `Contents/Library/LaunchDaemons`,
one daemon per module, never shared between modules — and both gate on the
signing decision: their code-signing requirements pin a real Team ID, so ad-hoc
suite builds cannot carry phase 3's helpers. The signing open question in
PLAN.md sits on phase 3's critical path, not in a later distribution pass.

Rejected for now: **depend on the tool repos as remote Swift packages.** It
preserves a single source of truth per core, but it couples the suite's build
to ten repos' cadences and pins the suite to each repo's release discipline.
Revisit only if the standalone apps stay alive long-term — at that point the
shared cores could be extracted into their own tiny packages both sides
consume.

## Module applicability

`SuiteModule` says what a tool is, not whether it can run on this Mac. Its
`Status` is only `planned` or `available`. Before the first module ships, the
descriptor also states:

- **Minimum OS**, for the pane and the watcher separately where they differ.
  Example: the HallPass feature needs macOS 15.5, the first release with the
  exemption defaults it edits
  ([TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)).
  The suite itself declares macOS 14.
- **Required environment**, checked cheaply and without a prompt: a Docker
  endpoint for DockVac, a Zen profile for Zen Backup Manager, installed
  runners for RunningMan.

An inapplicable module never runs its watcher, never surfaces a suggestion and
never opens a pane that cannot work. Showing it with the reason or hiding it
is a UI decision. Declared floors per module are in
[modules.md](modules.md#platform-floors).

## Testing strategy

- `MurtenCore`: registry invariants, dedupe/snooze/threshold rules, deep-link
  parsing — pure and fully unit-testable.
- Each `<Tool>Core` keeps the test suite it brings with it.
- Before the first module ships, add macOS app-level smoke tests for
  home/suggestion/pane routing, cancellation and focus with fake services.
  Keyboard, VoiceOver, contrast and text-size acceptance live in
  [UI direction](ui-direction.md#accessibility-acceptance);
  unit tests and screenshots do not substitute for these checks.
- Watcher behaviour is tested against fixture command output, never the real
  system (same boundary discipline as DeviceControlDoctor's `ProcessRunner`).
  Fake clocks and services cover threshold oscillation, multiple targets,
  snooze/restart, resolution/recurrence, partial/failing observations, timeout,
  wake coalescing, opt-out during a poll, late results and stale deep links.
- The privileged write paths stay manual-verification-only, exactly as in the
  standalone apps, and stay documented as such.
