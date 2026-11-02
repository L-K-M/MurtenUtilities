# MurtenUtilities

> [!IMPORTANT]
> LLM disclosure: This codebase was written with substantial help from large language models: AI coding agents working from the [`AGENTS.md`](AGENTS.md) brief in this repo.

**Latest release:** v<!-- version -->0.1.0<!-- /version --> · [Download](https://github.com/L-K-M/MurtenUtilities/releases/latest)

Murten Utilities is a friendly Mac toolbox in the spirit of Norton Utilities
for System 7 and Mac OS 8: one app, a classic-looking home screen of small
focused tools, and an opt-in menu-bar companion that quietly notices when a
tool would help — "Docker is holding ~8 GB" — and deep-links you to the right
pane. Detection and repair stay separate: nothing is cleaned, reset or removed
without an explicit click.

The design and migration plan lives in [PLAN.md](PLAN.md) and [docs/](docs/).
The app is early scaffolding: the home window already lists the planned
modules, and the first real tool migrates next.

## Building

```sh
swift build              # the package
swift test               # MurtenCore tests
./scripts/build-app.sh   # dist/MurtenUtilities.app, ad-hoc signed (--debug, --universal)
```

`scripts/build.sh` / `scripts/release.sh` wrap the shared `lkm-build` /
`lkm-release` engines; releases are cut by tagging — see [CICD.md](CICD.md).
Requires macOS 26 and Xcode 26 (CI pins the toolchain). The classic chrome comes from
[Rigi](https://github.com/L-K-M/Rigi), pinned to an immutable commit in
`Package.swift`.

## License

MurtenUtilities's own code is released under the [Unlicense](LICENSE). The app
bundle embeds [Rigi](https://github.com/L-K-M/Rigi), which keeps its own
license.
