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
- All ten rostered tools: DockVac, RepoMen, BootCaptain,
  DeviceControlDoctor, Shortking, HallPass, Zen Backup Manager, Obtainintosh,
  RunningMan and Coreography, with their panes, tests and eligible watchers.
- Ad-hoc builds omit BootCaptain and Coreography's privileged helpers; their
  helper-backed actions remain disabled until a Developer ID build.

### Changed

- Deployment floor raised to macOS 26.
- Locked the app's appearance to light (`NSRequiresAquaSystemAppearance`) —
  a documented product decision, not a missing feature; dark mode would be a
  Rigi redesign, not a reskin.

### Fixed

- RepoMen now applies every completed measurement before marking a scan ready.
- BootCaptain serializes journal access across concurrent tasks.

## [0.1.0] - 2026-11-01

### Added

- Initial project scaffold: SwiftPM package with `MurtenCore` (module registry,
  suggestion model, watcher protocol) and the `MurtenUtilities` app shell
  (SwiftUI home window + menu-bar companion, RigiUI status bar).
- Standard fleet plumbing: CI, tag-driven releases (universal `.zip` + `.dmg`),
  automated PR review, Dependabot, and the build/release engine stubs.
- Product plan: `PLAN.md`, `docs/architecture.md`, `docs/modules.md`,
  `docs/ui-direction.md`.
