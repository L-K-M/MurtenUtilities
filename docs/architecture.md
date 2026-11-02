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

Two extension points everything hangs off:

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
  cheap and must not require privilege *to look*. `docker system df` is the
  canonical example. A check that needs privilege is a tool action, not a
  watcher.
- **Rules** turn a finding into at most one suggestion per `key`. Thresholds
  ("≥ 4 GB reclaimable", "≥ 1 runner offline ≥ 10 min") live with the module.
- **SuggestionStore** dedupes by `key` (a repeated finding refreshes, never
  stacks), applies per-category snoozes and a global rate limit, and persists
  to `~/Library/Application Support/MurtenUtilities/suggestions.json`.
- **Surfaces**: home-screen feed, menu-bar badge count, and — only where the
  user opted in per category — `UNUserNotification`. Never modal.
- **Deep links**: `murten://<moduleID>[/<action>]` inside the app; each pane
  can register a payload (e.g. DockVac's "reclaimable set selected").

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

- `MenuBarExtra` is the resident face; it costs nothing when the window is
  closed but does **not** launch at login by itself.
- Launch at login is an explicit Settings toggle →
  `SMAppService.mainApp.register()` / `.unregister()`.
- Watchers pause sensibly (on battery? metered network? user "quiet hours"?) —
  a Settings section, designed before the first watcher ships.

## Module packaging

Chosen: **migrate code in.** Each tool's pure core becomes a `<Tool>Core`
target in this package (or merges into `MurtenCore` when tiny); its pane lives
in the app. The source repos are small and mostly single-purpose, so code
moves cleanly; the standalone apps keep working from their own history.

Rejected for now: **depend on the tool repos as remote Swift packages.** It
preserves a single source of truth per core, but it couples the suite's build
to ten repos' cadences and pins the suite to each repo's release discipline.
Revisit only if the standalone apps stay alive long-term — at that point the
shared cores could be extracted into their own tiny packages both sides
consume.

## Testing strategy

- `MurtenCore`: registry invariants, dedupe/snooze/threshold rules, deep-link
  parsing — pure and fully unit-testable.
- Each `<Tool>Core` keeps the test suite it brings with it.
- Watcher behaviour is tested against fixture command output, never the real
  system (same boundary discipline as DeviceControlDoctor's `ProcessRunner`).
- The privileged write paths stay manual-verification-only, exactly as in the
  standalone apps, and stay documented as such.
