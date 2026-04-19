# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Native macOS FM composite (MPX) generator — real-time broadcast-style stereo encoder with RDS. Swift 6 / SwiftUI / AVAudioEngine, SPM package rooted at `macOS/`. Targets macOS 15+. Single executable target `MPXPrime`; sole external dep is `swift-atomics`.

See also: `AGENTS.md` (workflow rules, HIG), `ARCHITECTURE.md` (detailed DSP chain and stage descriptions), `plan.md` (roadmap).

## Commands

```bash
# Build (debug / release)
swift build --package-path macOS
swift build --package-path macOS -c release

# Run
swift run --package-path macOS MPXPrime              # GUI
swift run --package-path macOS MPXPrime --nogui      # headless
swift run --package-path macOS MPXPrime --config "/path/to/MPX Prime.ini"

# Offline verification (no audio devices touched)
swift run --package-path macOS MPXPrime --verify --seconds 5
swift run --package-path macOS MPXPrime --verify-presets --seconds 5
swift run --package-path macOS MPXPrime --verify-long --seconds 30

# Baseline capture + strict compare
swift run --package-path macOS MPXPrime --capture-baseline      # writes macOS/verifier_baselines/default.json
swift run --package-path macOS MPXPrime --verify --baseline-strict

# Tests — MUST override DEVELOPER_DIR; CLT ships no Testing.framework, Xcode does.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path macOS

# Single test / filter
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path macOS --filter BassClipperTests

# Release bundle + DMG
./build-release.sh 0.9
```

Verifier exit codes: `0` = PASS, `1` = TIGHT (near limits, review), `2` = WARN.

Tests use **Swift Testing** (`import Testing`, `@Test` / `#expect`) — not XCTest. Do not add XCTest-based tests.

## Architecture

### Layout
- `macOS/Sources/MPXPrime/` — all runtime code (no sub-modules)
  - `main.swift` — CLI entry, arg parsing, verify-mode dispatch
  - `AppConfig.swift` — INI-backed config model + live-apply routing (`RuntimeConfig`)
  - `INIParser.swift`, `AudioDevices.swift` — file and CoreAudio plumbing
  - `AudioOutputEngine.swift` — AVAudioEngine lifecycle, input tap, render callback
  - `MPXGenerator.swift` (~6200 lines) — DSP core. All stages of the chain live here
  - `StereoInputRingBuffer.swift` — lock-free input → render bridge
  - `SwiftUIControlApp.swift` (~6800 lines) — SwiftUI views + view-model state
  - `VerificationHarness.swift` / `VerifierBaseline.swift` — offline scenario renderer + baseline compare
  - `NowPlayingSupport.swift` — external script polling for RDS RT metadata
- `macOS/Tests/MPXPrimeTests/` — Swift Testing suite (DSP primitives, ring buffer, analysis helpers)
- `macOS/verifier_baselines/` — JSON baselines + `ClipperAliasingBaseline.md` documenting pre-Phase-7.1 aliasing so post-refactor deltas are attributable
- `macOS/{MPXPrime.ini,Verification.ini}` — sample configs; user config lives at `~/Library/Application Support/MPX Prime/MPX Prime.ini`
- `documents/` — standards PDFs (EN 50067 / IEC 62106 etc.)

### Signal chain (critical invariants)

The audio path runs ~24 stages, ending with **post-limiter pilot + RDS injection**. Anything that touches the chain order needs to preserve two non-obvious invariants:

1. **Subcarriers (19 kHz pilot, 57 kHz RDS) MUST be injected after all limiting.** They bypass composite limiter, composite clipper, BS.412, and safety limiter. Constant-amplitude subcarriers are required for reliable stereo decoding and RDS reception — this matches professional broadcast practice (Omnia, Orban, Stereotool).
2. **Pre-emphasis runs in L/R domain before the pre-encode limiter**, not in M/S after the limiter. This is so the L/R limiter can peak-control the 10–12 dB HF boost. Moving pre-emphasis back into M/S silently breaks peak control.

Two-stage limiting:
- **Pre-encode audio limiter** — L/R, stereo-linked, after pre-emphasis, before stereo encoding.
- **Composite limiter** — 4× oversampled true-peak on the audio composite after stereo encoding. Its decimation LP is tuned to ~57.6 kHz @ 192 kHz — **do not** swap for a memoryless clipper; harmonic distortion bleeds into the 57 kHz RDS band.

`Mono Mode` suppresses pilot, stereo subcarrier, and RDS — true mono composite.

Oversampled clippers (BassClipper 4×, DistortionCancelledClipper 8×, CompositeClipper 8×) share a `Lagrange4Interp` + `BiquadCascade6` pattern (12th-order Butterworth decimation LP). Follow this pattern for any new oversampled nonlinearity.

### Configuration + live-apply

`AppConfig` maps INI keys to runtime settings. Many DSP params are **live-apply** via `RuntimeConfig` (no engine restart). A few are restart-only. When adding a setting, classify it explicitly — the README and `plan.md` track open smoke-test gaps here.

Verification.ini key name collisions are a known sharp edge: an INI key that looks like it controls stage X but is wired to stage Y will silently disable the wrong thing. Grep `AppConfig.swift` for the exact config-key string before adding a new one (e.g. don't name a composite-clipper toggle `composite_clipper_enabled` — that's already mapped to the composite *limiter*; use `mpx_clipper_*` keys).

### Threading

- **Audio render callback**: real-time thread. Lock-free, allocation-free. No blocking I/O, no dispatch, no `Task { ... }`, no string formatting, no `NSRegularExpression` compilation. Cache compiled regex as `static let`.
- **Main thread**: SwiftUI UI. For timer callbacks into `@MainActor` state, use `MainActor.assumeIsolated {}`, **not** `Task { @MainActor in ... }` — the latter heap-allocates and accumulates pressure on long-running meters.
- **Background metering**: `.userInteractive` QoS dispatch queue. Skip calculations when `meteringEnabled` is false (UI not visible).

Hot-path optimization: prefer `vDSP_*` (Accelerate) over Swift loops. Pre-allocate buffers at engine start. Use `@inline(__always)` on tiny hot helpers.

## Conventions

- **ASCII only** in source and docs. No non-ASCII punctuation / symbols.
- Keep `MPXGenerator.swift` and `SwiftUIControlApp.swift` splittable-in-principle (both >6k lines); prefer new helpers over growing them further, but **do not** opportunistically refactor the final MPX chain — even behavior-preserving edits can measurably move composite output. Structural cleanup there is done in small, verifier-backed steps.
- No buttons in title bars / toolbars. Use `HSplitView` for static sidebars, `NavigationSplitView` only when collapse is needed. Cards use `LabeledContent`, 10pt corner radius, 16pt spacing. `.buttonStyle(.bordered[Prominent])`, `.pickerStyle(.segmented)` or `.menu`.
- Device UIDs are platform-specific — always enumerate, never hardcode.
- New DSP stages ship **disabled by default** and must support live-apply via `RuntimeConfig` unless there is a specific reason not to.
