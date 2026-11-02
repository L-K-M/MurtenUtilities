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

## Privilege model

Merging tools into one binary must not union their privileges. The rules:

- The app itself asks for nothing ambiently. TCC-sensitive *observation* stays
  read-only and per-module.
- A repair path belongs to its module and asks at write time — e.g. the
  HallPass module keeps its osascript write boundary; the DeviceControlDoctor
  module keeps its confirmed `tccutil reset`; DockVac keeps its Docker socket
  use scoped to the delete action.
- If a module ever needs a privileged helper (it shouldn't, for the confirmed
  roster), it ships an `SMAppService`-registered helper for that module only —
  never a suite-wide root daemon.

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
