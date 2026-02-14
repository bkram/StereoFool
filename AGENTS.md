# Agent Instructions

## Project basics

- Primary entrypoint: `macOS/Package.swift`
- Config file: `macOS/StereoFool.ini`
- Native macOS app built with Swift + SwiftUI

## How to run

```bash
swift run --package-path macOS StereoFool
```

Default runs with GUI. Use `--nogui` for headless mode.

## Code change guidance

- Keep runtime DSP in `macOS/Sources/StereoFool/` - prefer small, testable helpers.
- SwiftUI views in `SwiftUIControlApp.swift` - keep lightweight.
- Avoid reintroducing separate Stereo/RDS menus; use unified navigation.
- Avoid adding non-ASCII characters to source or docs.

## Testing

- Manual smoke test: start the app with `--gui` and verify audio output.
- Build with `swift build --package-path macOS` (debug) or `swift build --package-path macOS -c release` (production).

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
- RDS baseband uses EN 50067 biphase shaping and a pilot-locked subcarrier.
- Standards reference PDFs live in `documents/`.
