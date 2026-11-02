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

## SuggestionStore

The `SuggestionStore` is the central coordinator for the suggestion pipeline. It:

- Deduplicates suggestions by `key` (a repeated finding refreshes the existing suggestion instead of stacking).
- Applies per-category snooze rules (e.g., "don't show this again for 24 hours").
- Enforces a global rate limit (e.g., ≤ 3 suggestions per hour) to prevent spam.
- Persists active suggestions to `~/Library/Application Support/MurtenUtilities/suggestions.json` (JSON format, one record per suggestion).
- Loads persisted suggestions on app launch and prunes expired snoozes.
- Emits notifications when the suggestion feed changes (e.g., for the menu-bar badge).

### Persistence format

```json
{
  "suggestions": [
    {
      "key": "dockvac.reclaimable",
      "moduleID": "dockvac",
      "title": "Docker is holding ~8 GB",
      "detail": "Unused images and build cache.",
      "lastUpdated": "2024-06-05T12:00:00Z",
      "snoozeUntil": "2024-06-06T12:00:00Z"
    }
  ]
}
```

### Error handling

- If persistence fails (e.g., disk full), the store logs the error and continues in-memory.
- If a watcher fails, the store marks the suggestion as "stale" and removes it after a timeout.
- If a module is uninstalled, its suggestions are pruned.

### Testing

- Unit tests for dedupe, snooze, and rate-limiting logic.
- Integration tests for persistence and deep-link routing.
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
- Two confirmed modules already ship a privileged helper: BootCaptain's
  code-signing-pinned XPC helper (Mach service `ch.lkmc.bootcaptain.helper`)
  and Coreography's XPC daemon (`CoreographyHelper`, registered through
  `SMAppService.daemon`). Each keeps its own helper and install path — SMJobBless
  or a bundled daemon plist, not the login-item `SMAppService` above — and never
  a suite-wide root daemon. Their code-signing requirements pin a real Team ID,
  so they also settle the signing question (see PLAN.md).

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
