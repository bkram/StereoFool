# StereoFool macOS

StereoFool is a native macOS FM stereo / MPX / RDS app built with Swift, SwiftUI, and AppKit.

## Build

```bash
swift build --package-path macOS
```

Release build:

```bash
swift build --package-path macOS -c release
```

## Run

From repo root:

```bash
swift run --package-path macOS StereoFool
```

Default launch mode is GUI.

Headless mode:

```bash
swift run --package-path macOS StereoFool --nogui
```

Custom config path:

```bash
swift run --package-path macOS StereoFool --config /path/to/StereoFool.ini
```

## Default configuration path

```text
~/Library/Application Support/StereoFool/StereoFool.ini
```

## UI overview

Main app sections:

- `Monitoring`
- `Processing`
- `RDS`

Settings contains:

- configuration utilities
- interfaces
- audio engine settings
- spectrum options

Separate windows:

- `Scopes`
- `Spectrum`
- `Levels`
- `Help`

## Output behavior

- `MPX Output Device` is the baseband output device
- `Monitor Output Device (Decoded MPX Simulation)` is used when monitor output is enabled
- closing the main window keeps the app running; reopen it from the Dock or Window menu

## DSP notes

- default input HPF: `30 Hz`
- default program lowpass: `16.4 kHz`
- default scope auto gain: enabled
- bypass keeps the FM encode path active and disables creative processing blocks only

## Build release app / DMG

```bash
./build-release.sh 0.8
```

Artifacts are written to `macOS/dist/`.
