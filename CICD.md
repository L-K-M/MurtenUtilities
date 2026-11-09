# CI/CD

MurtenUtilities is a SwiftPM package plus a SwiftUI app in one repository —
no `.xcodeproj` — so its CI builds and tests with `swift build` / `swift test`,
then proves the packaging path by running `scripts/build-app.sh --universal`
into `dist/MurtenUtilities.app`. The release workflow does the same on a tag
and publishes an unsigned, ad-hoc-codesigned `.zip` and `.dmg` as a GitHub
Release.

## Workflows

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `.github/workflows/ci.yml` | Pull requests, pushes to `main`, manual dispatch | License/bundle-id assertions, `swift build`, `swift test`, universal `.app` assembly on a pinned Xcode toolchain. |
| `.github/workflows/zai-code-review.yml` | Pull requests (opened / reopened / synchronize / ready for review) | Automated review pass with GLM 5.3 (deep) and MiMo v2.6 Pro (fast tier), with StepFun step-5-preview as the last-resort fallback. |
| `.github/workflows/release.yml` | Pushing a `v*` tag (e.g. `v1.2.0`) | Re-run tests, build the universal `.app`, package `.zip` + `.dmg`, publish a GitHub Release, then byte-compare the published assets. |

## Continuous integration (`ci.yml`)

One job on `macos-26` selecting **Xcode 26.0** via `maxim-lobanov/setup-xcode` —
pinned so a runner-image bump can't silently change the toolchain. The app's
deployment target is macOS 26 (`LSMinimumSystemVersion`, `Package.swift`). The build fetches the pinned Rigi revision from
GitHub like any other SwiftPM dependency. In-progress runs for the same *PR
branch* are cancelled on a new push; main-branch runs are never cancelled.

Third-party actions are pinned to immutable commit SHAs for the same reason
`zai-code-review.yml` pins its action.

`workflow_dispatch` is enabled. It was added family-wide when GitHub throttled
webhook delivery during an Actions incident and `pull_request` events stopped
starting workflows at all; dispatch goes through the API instead. It is worth
keeping regardless — re-running CI no longer needs an empty commit.

### Running CI checks locally

```sh
swift build
swift test
./scripts/build-app.sh --universal
```

This requires Xcode 26 to match CI (any Xcode 16+ builds the package; the pin
keeps CI deterministic).

## PR review (`zai-code-review.yml`)

Identical to the workflow in every other repo in the family, including its
hardening:

- It is a `pull_request_target` workflow, which exposes repository secrets and a
  write-capable token, so it **only runs for branches in this repository** —
  never for a fork's.
- The third-party action is pinned to an immutable commit rather than a moving tag.
- One review per PR at a time; a superseded review of an outdated diff is cancelled.
- `ZAI_API_KEY` is required; `MIMO_API_KEY` and `STEPFUN_API_KEY` are optional —
  empty secrets keep the dedicated fast tier and the outage fallback disabled.
- Note: because `pull_request_target` reads the workflow from the base branch, a
  PR that introduces this file is not itself reviewed; reviews start with the
  next PR.

Findings are advice, not a gate. `CLAUDE.md` in this repo describes how to
triage them — apply, decline with recorded reasons, or refute with evidence —
and when to stop.

## Releases (`release.yml`)

```sh
scripts/release.sh 1.2.0 --push   # bump Resources/Info.plist + README marker, commit, tag v1.2.0, push
```

The tag triggers `release.yml`, which gates publication on `swift test`, builds
the universal `.app` via `scripts/build-app.sh --universal`, stamps
`CFBundleVersion` with the run number and `CFBundleShortVersionString` with the
tag version, then packages `MurtenUtilities-<vX.Y.Z>-macos-universal.zip` and
`.dmg`. A post-publish step downloads what GitHub actually serves and
byte-compares it against the build output, removing a mismatched asset rather
than serving it.

**Why unsigned.** The app is ad-hoc signed (`codesign --sign -`), which Apple
Silicon requires to launch, but carries no Developer ID signature and is not
notarized — CI needs no Apple credentials this way, and macOS Gatekeeper warns
on first launch. The release notes tell users how to open it. Nothing here
precludes adding Developer ID signing later; the workflow's only change would
be in the sign step, and `scripts/build-app.sh` already honours
`CODE_SIGN_IDENTITY` for stable local signatures.
