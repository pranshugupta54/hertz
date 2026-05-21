# Contributing to Hertz

Thanks for helping out. Hertz is a small, focused Swift app — keep changes
that way too.

## Setup

Requires macOS 14+ and the Xcode Command Line Tools:

```sh
xcode-select --install
git clone https://github.com/pranshugupta54/hertz.git
cd hertz
```

## Project layout

```
Sources/HertzCore/    Metric collectors — Mach, libproc, IOKit, SMC, CoreWLAN
Sources/Hertz/        The SwiftUI menu-bar app (MenuBarExtra)
Sources/HertzVerify/  Dev-only tool that cross-checks every metric
scripts/              bundle.sh (build the .app), makeicon.sh, Info.plist
.github/workflows/    release.yml — builds + publishes on a version tag
```

**Read [ARCHITECTURE.md](ARCHITECTURE.md)** for the full picture — targets,
data flow, every collector, the metric-accuracy gotchas, the auto-update
mechanism, and the release pipeline. Skim it before a non-trivial change.

## Build and run

```sh
swift build                       # build everything
swift run Hertz                  # run the app from the terminal
swift run HertzVerify            # cross-check metrics vs df/vm_stat/top/...
./scripts/bundle.sh               # produce Hertz.app
```

## Verify your changes

If you touch a collector, run the verifier — it compares every metric against
an independent system command (`df`, `vm_stat`, `top`, `ps`, `pmset`, `ioreg`)
and must report `ALL CHECKS PASSED`.

## Conventions

- Swift 6.2, `swift-tools-version:6.2`. The targets are `MainActor`-isolated
  by default (`defaultIsolation`); keep collectors synchronous.
- No third-party dependencies. Everything is OS APIs.
- Match the surrounding style: small structs, comments that explain *why*.
- UI stays flat and native — no gradients, no faux-glass.

## Pull requests

1. Branch off `main`.
2. Keep the change focused; update docs if behaviour changes.
3. `swift build` clean and `swift run HertzVerify` passing.
4. Open the PR with a short description of what and why.
