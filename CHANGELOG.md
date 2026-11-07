# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The suite spine: findings and rules, a persisted suggestion ledger
  (episodes, snooze, dismissal, staleness, throttled opt-in notifications),
  the watch coordinator (cadence, timeouts, back-off, pauses, cancellation),
  validated `murten://` routes, and the `SuiteModuleProvider` contract.
- Home window with the suggestion feed, opt-in menu-bar companion, Settings
  (background checks, per-module notifications, pauses, launch at login,
  update checks off by default), Tool menu and module windows.
- All ten rostered tools: Docker Cleaner, Developer Cleanup, Startup Manager,
  App Permission Checkup, Shortcut Detective, Local Network Access, Zen
  Session Recovery, Software Update Finder, CI Runner Manager and System
  Monitor, with their panes, tests and eligible watchers.
- App Permission Checkup can reset every Device Control and Data Access
  decision after inventorying all recorded clients, safely quitting affected
  apps, and verifying they remain closed before each service-wide reset.
- Ad-hoc builds omit Startup Manager and System Monitor's privileged helpers;
  their helper-backed actions remain disabled until a Developer ID build.

### Changed

- Distinct actions and compositions for all ten tool illustrations: container
  extraction, sweeping, a startup lever, keyhole inspection, a lounging
  keyboard detective, cable joining, seated recovery, a download ladder,
  sprinting CI stages and a seated monitor operator.
- The app icon is a colourful retro Mac workshop, with a perched helper
  and a large wrench on a sunflower-yellow plate.
- The ten tool icons now use colourful flowing stick figures, with larger
  artwork in the home tiles and matching illustrations in suggestions and
  background-check settings.
- Deployment floor raised to macOS 26.
- Modules use descriptive, task-oriented names instead of their source app
  brands; stable routes, settings and on-disk formats are unchanged.
- Locked the app's appearance to light (`NSRequiresAquaSystemAppearance`) —
  a documented product decision, not a missing feature; dark mode would be a
  Rigi redesign, not a reskin.

### Fixed

- Opened up the tool figures' cramped torso proportions and made artwork
  fitting uniform in non-square frames. App-icon resampling retains alpha.
- Widened the System Monitor illustration's screen and kept the ten-tool
  home grid within the default window without a scrollbar.
- Prevented a startup freeze or crash when the menu-bar companion is off.
- Developer Cleanup now applies every completed measurement before marking a
  scan ready.
- Startup Manager serializes journal access across concurrent tasks.

## [0.1.0] - 2026-11-01

### Added

- Initial project scaffold: SwiftPM package with `MurtenCore` (module registry,
  suggestion model, watcher protocol) and the `MurtenUtilities` app shell
  (SwiftUI home window + menu-bar companion, RigiUI status bar).
- Standard fleet plumbing: CI, tag-driven releases (universal `.zip` + `.dmg`),
  automated PR review, Dependabot, and the build/release engine stubs.
- Product plan: `PLAN.md`, `docs/architecture.md`, `docs/modules.md`,
  `docs/ui-direction.md`.
