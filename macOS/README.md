# MPX Prime macOS

MPX Prime is a native macOS FM stereo / MPX / RDS app built with Swift, SwiftUI, and AppKit.

Current release line: `0.85`

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
swift run --package-path macOS MPXPrime
```

Default launch mode is GUI.

Headless mode:

```bash
swift run --package-path macOS MPXPrime --nogui
```

Custom config path:

```bash
swift run --package-path macOS MPXPrime --config "/path/to/MPX Prime.ini"
```

## Default configuration path

```text
~/Library/Application Support/MPX Prime/MPX Prime.ini
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
- `Mono Mode` transmits true mono composite only and suppresses pilot, stereo subcarrier, and RDS while enabled
- closing the main window keeps the app running; reopen it from the Dock or Window menu

## DSP notes

- default input HPF: `30 Hz`
- default program lowpass: `16.4 kHz`
- default scope auto gain: enabled
- default `Final Drive`: `6 dB`
- default wideband AGC target: `-16 dB`
- default `Mono Bass`: enabled at `125 Hz`
- bypass keeps the FM encode path active and disables creative processing blocks only
- the limiter tab contains the main loudness controls and telemetry
- the widener tab now includes a dedicated mono-bass stage in addition to the stereo widener

## Build release app / DMG

```bash
./build-release.sh 0.85
```

Artifacts are written to `macOS/dist/`.
