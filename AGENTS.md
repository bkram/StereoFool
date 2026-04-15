# Agent Instructions

## Project basics

- Primary entrypoint: `macOS/Package.swift`
- Default config file: `~/Library/Application Support/MPX Prime/MPX Prime.ini`
- Native macOS app built with Swift + SwiftUI

## How to run

```bash
swift run --package-path macOS MPXPrime
```

Default runs with GUI. Use `--nogui` for headless mode.

## Code change guidance

- Keep runtime DSP in `macOS/Sources/MPXPrime/` - prefer small, testable helpers.
- SwiftUI views in `SwiftUIControlApp.swift` - keep lightweight.
- Avoid reintroducing separate Stereo/RDS menus; use unified navigation.
- Avoid adding non-ASCII characters to source or docs.

## UI/UX Guidelines (Apple HIG)

- **No buttons in the title bar** - All controls must be in the content area, not in the toolbar or title bar.
- Use native macOS window chrome (standard title bar with close/minimize/zoom buttons).
- Use `HSplitView` for sidebar layout (not `NavigationSplitView` if collapse is not needed).
- Use `NavigationSplitView` only when sidebar collapse is required.
- Use `.listStyle(.sidebar)` for sidebar navigation.
- Use standard macOS form styling with `Card` components using `LabeledContent`.
- Use `.buttonStyle(.bordered)` and `.buttonStyle(.borderedProminent)` for buttons.
- Use `.pickerStyle(.segmented)` for tab pickers within sections.
- Use `.pickerStyle(.menu)` for dropdown pickers.
- Card corner radius: 10pt.
- Spacing between cards: 16pt.

## Testing

- Manual smoke test: start the app with `--gui` and verify audio output.
- Build with `swift build --package-path macOS` (debug) or `swift build --package-path macOS -c release` (production).
- Unit tests use Swift Testing (`import Testing`, not XCTest). Run with:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path macOS`
  The `DEVELOPER_DIR` override is required because the Command Line Tools toolchain does not ship `Testing.framework` on its own search path; Xcode does. Without it, `swift test` fails with `no such module 'Testing'`.
- `ClipperAliasingBaseline.md` in the test target documents the pre-Phase-7.1 aliasing measurements so post-refactor deltas are attributable.
- CPU profiling: use Instruments (Time Profiler) to verify DSP optimizations.

## Release prep

- Before release, use this checklist:
  - Update version in `CHANGELOG.md` and README as needed.
  - Run `swift build --package-path macOS -c release` successfully.
  - Manual smoke test: run with `--gui`, verify monitoring and processing work.
  - Clean up `.build` artifacts if needed.

## Notes

- Audio device UIDs are platform-specific; use device enumeration, avoid hardcoding IDs.
- Real-time DSP is sensitive to blocking I/O; keep audio callbacks lock-free and allocation-free.
- RDS carrier frequency is config-only; UI exposes carrier level and program data.
- The monitoring view includes scopes, MPX meters, and limiter status; keep it lightweight.
- The processing chain includes phase rotation, parametric EQ, mono-bass, stereo-image control, Orbass, multiband (with per-band limiter and downward expander), bass clipper, distortion-cancelled clipper, and the final MPX stage with BS.412 power limiting.
- RDS baseband uses EN 50067 biphase shaping and a pilot-locked subcarrier.
- Standards reference PDFs live in `documents/`.

## CPU Optimization

When profiling shows high CPU usage:

1. Use `vDSP_*` functions from Accelerate framework for vectorized operations (faster than Swift loops)
2. Throttle UI-related computations (meters, scopes) - they don't need to run every audio callback
3. Use `@inline(__always)` on small hot-path functions
4. Pre-allocate buffers to avoid runtime allocations in audio callbacks
5. Use `meteringEnabled` flag to skip meter/scope calculations when UI isn't visible
