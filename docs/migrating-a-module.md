# Migrating a module

How a standalone fleet app becomes a suite module. The contracts are in
[architecture.md](architecture.md); this page is the checklist.

## Targets

Copy code in (PLAN.md, *Migrate code in*); do not depend on the tool repo.

```
Sources/<Tool>Core/       pure logic, moved as is (keep its name: DockVacCore, DoctorCore…)
Sources/<Tool>Services/   IO the pane and watcher share, when the source has it
                          (keep existing names: DockVacDocker, RunningManServices…)
Sources/<Tool>Module/     the pane, the watcher, the provider. A library, so tests can import it.
Tests/<Tool>CoreTests/    the source's tests, moved with the code
Tests/<Tool>ModuleTests/  the watcher and rule against fixtures, the provider's routes
```

- Keep each source target's Swift language mode (`swiftSettings:
  [.swiftLanguageMode(.v6)]` when the source used 6).
- Fill in the module's own block in `Package.swift` (`<tool>Targets`,
  `<tool>Module`), set its factory in
  `Sources/MurtenUtilities/Catalog/<Tool>.swift`, and set the descriptor's
  `status: .available` in `ModuleRegistry`. Each module has its own block
  and file so parallel migrations merge cleanly; stay inside yours.
- Tests that `@testable import` the source's executable move to
  `<Tool>ModuleTests` against the module library.
- Command-line tools (`coreo`, BootCaptain's CLI) stay in their repos.
- No third-party dependencies (AGENTS.md).

## Provenance

Record the upstream commit the code was copied from in the module's own
section of docs/modules.md (`- **Provenance:** <repo>@<commit>`), so fixes
on either side can be found later.

## The provider

Implement `SuiteModuleProvider` (`Sources/MurtenModuleKit`). The shell
creates it once at launch with a `ModuleContext`:

- Long-lived state (a scan, a selection, a cleanup in progress) lives in the
  provider or an object it owns, not in the pane view. Navigating home and
  back rebuilds the view.
- `makePane(route:)` returns the pane. AppKit panes wrap their view
  controller in `NSViewControllerRepresentable`.
- `routeActions` lists the actions a suggestion may open with and the
  context keys each accepts. The route preselects only what the module's
  rule in docs/modules.md (*What a suggestion may preselect*) allows.
  Opening never starts a repair; the pane re-scans and asks.
- `applicability()` is cheap and never prompts: a missing Docker endpoint,
  no Zen profile, no runners.
- `interruptionWarning` replaces quit guards ("A cleanup is still
  running"). Unsaved-draft prompts move into the pane itself.
- `makeSettings()` replaces the source's `Settings` scene.
- Auxiliary windows (a test pad, a log) come from `makeWindow(_:)`; panes
  open them with `openWindow(module: ModuleWindowRequest(...))`.
- Menu commands and their shortcuts: publish them with
  `.moduleCommands([...])`; they appear in the Tool menu while the pane is
  focused.
- A source app's own menu-bar extra folds into the suite's companion:
  `makeMenuSection()` returns a compact view shown there (live
  instruments, a review count, armed automation). Keep it small; it is a
  panel, not a second app.

## User-armed automation

Only RepoMen's Watch mode (PLAN.md, *User-armed automation*): armed per
target by the user, off by default, reversible (to the Trash), visible in
the module's menu section while armed, and run only while
`context.backgroundWorkAllowed()` is true. It is module code, never the
watcher: the watcher still only observes.

## What the shell owns

Remove these from the migrated code; the suite has exactly one of each:

- `@main`, `App`, `NSApplicationDelegate`, `NSApp.mainMenu`/`windowsMenu`,
  activation policy, `applicationShouldTerminateAfterLastWindowClosed`,
  window-delegate takeovers.
- `MenuBarExtra`, launch at login (`SMAppService.mainApp`), notifications
  (`UNUserNotificationCenter`), Dock badges.
- Self-update checks (architecture.md, *Module packaging*).
- Background timers and monitors. Periodic checks become the module's
  `Watcher`, scheduled by the suite, opt-in, paused by the user's settings.
  Work while the pane is visible may still poll.
- `NSApp.terminate`, `CommandLine.arguments`, `Bundle.main` identity checks
  (`Bundle.main.bundleIdentifier` is the suite's now).

## Watcher and rule

- The rule (`SuggestionRule`) is pure: put it in `<Tool>Core`. The watcher
  goes in `<Tool>Services` or `<Tool>Module`, behind an injectable
  observation-only interface, and is tested against fixtures, never the
  live system.
- A watcher never writes, never needs privilege and never prompts. A check
  that needs any of those is a pane action.
- Report every scope it checked; report failures as failures, not as
  "nothing found" (`WatchObservation`).
- Pick a cadence of at least 15 minutes and declare `.network` when the
  check talks to a remote host.

## State

- Preferences: `context.defaults` (the shell also installs it as the
  pane's `@AppStorage` store). Keys stay as they were; the domain is
  per module, so they cannot collide.
- Files the standalone app keeps, especially undo data, stay where they are
  (architecture.md, *Transition from the standalone apps*): read them in
  place, never start empty over them.
- Keychain items keep their service names; verify access before relying on
  a silent import.

## Resources

SwiftPM's generated `Bundle.module` looks for resource bundles at the app
bundle's root, where code signing forbids them. `scripts/build-app.sh`
copies them to `Contents/Resources`, so load resources through an accessor
that looks there first:

```swift
extension Bundle {
    static let dockVacModule: Bundle = {
        let name = "MurtenUtilities_DockVacModule.bundle"
        if let url = Bundle.main.resourceURL?.appendingPathComponent(name),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return .module // swift run and tests
    }()
}
```

## Language and look

- English UI throughout. HallPass's German strings are translated.
- Light appearance only; no dark-mode paths.
- Keyboard and VoiceOver: every action reachable, icons labelled.

## Finish

- Update docs/modules.md (status, provenance, watcher, preselection),
  README.md's module list and CHANGELOG.md.
- `swift build`, `swift test` and `scripts/build-app.sh --universal` pass in
  CI (`gh workflow run ci.yml --ref <branch>` runs it on a branch).
