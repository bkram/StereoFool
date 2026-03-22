# StereoFool

Version: 0.8

StereoFool is a native macOS FM composite (MPX) generator written in Swift and SwiftUI. It takes live audio input or a test tone, applies optional broadcast-style processing, generates stereo FM baseband with pilot and optional RDS, and sends MPX plus optional decoded monitor audio to Core Audio devices.

StereoFool is experimental and not suitable for production broadcast use. It targets core behavior from EN 50067 / IEC 62106 and common FM stereo practice, but it is not certified and no compliance warranty is implied.

## Current app structure

- `Monitoring`: live status, transport, interfaces summary, DSP status, RDS snapshot
- `Processing`: core DSP, AGC, Orbass, multiband, widener, limiter
- `RDS`: program, radiotext, long PS, flags, carrier
- `Settings`: configuration path, interfaces, audio engine, spectrum options
- Separate windows: `Scopes`, `Spectrum`, `Levels`, `Help`

## Features

- Native macOS app built with Swift + SwiftUI + AppKit windowing
- Real-time MPX generation with 19 kHz pilot and 38 kHz stereo subcarrier
- Optional RDS generation with pilot-locked 57 kHz subcarrier
- Live input source or built-in test tone source
- Optional wideband AGC, HPF, program lowpass, HF trim, Orbass, multiband, stereo widener
- MPX limiting and composite limiter status monitoring
- Decoded MPX monitor output on a selectable monitor device
- Scopes, spectrum, levels, sticky peaks, and live monitoring views
- Config persisted to `~/Library/Application Support/StereoFool/StereoFool.ini`

## Requirements

- macOS 15+
- Xcode command line tools / Swift 6 toolchain
- Core Audio device capable of your chosen output rate; 192 kHz is recommended for full stereo MPX output
- Input devices may run at lower rates; the app handles conversion internally

## Build

```bash
swift build --package-path macOS
```

## Run

From repo root:

```bash
swift run --package-path macOS StereoFool
```

Headless mode:

```bash
swift run --package-path macOS StereoFool --nogui
```

Fixed runtime:

```bash
swift run --package-path macOS StereoFool --seconds 10
```

Custom config file:

```bash
swift run --package-path macOS StereoFool --config /path/to/StereoFool.ini
```

## Configuration

Default config location:

```text
~/Library/Application Support/StereoFool/StereoFool.ini
```

Relevant config sections:

- `INTERFACES`: input/output/monitor device UIDs, source mode, monitor enable, block size
- `MPX`: processing, levels, stereo coding, limiter behavior
- `RDS`: program service, radiotext, flags, carrier settings

### Now Playing script output

The RDS Radiotext section can poll an external script for now-playing metadata.

Expected script behavior:

- Exit with status `0` when metadata is available
- Write metadata to `stdout`
- Plain single-line output is accepted and treated as the display text
- Structured `key=value` lines are preferred for correct RT+ tagging

Supported keys:

- `display`: full on-air text, for example `The Dizzy DJ - I Venti Megamix`
- `artist`: artist field for RT+
- `title`: title field for RT+
- `now_playing`: alias for `display`

Example script output:

```text
display=The Dizzy DJ - I Venti Megamix
artist=The Dizzy DJ
title=I Venti Megamix
```

Example Radiotext / RT+ settings:

```text
Radiotext: 10s:Now: {artist} - {title}
RT+ Format A: Now: {artist} - {title}
RT+ Format B: Now: {artist} - {title}
```

Available Radiotext macros:

- `{now_playing}`
- `{display}`
- `{artist}`
- `{title}`

Important defaults:

- Input HPF default: `30 Hz`
- Program lowpass default: `16.4 kHz`
- Scope auto gain default: enabled

## Monitoring and output notes

- `MPX Output Device` is the composite/baseband output device
- `Monitor Output Device (Decoded MPX Simulation)` is used when monitor output is enabled
- The orange microphone indicator in the macOS menu bar is the system privacy indicator and appears when StereoFool is actively using audio input

## Processing bypass

The `Bypass` control does not create a true wire bypass. It disables the creative processing blocks while keeping essential FM encode stages active.

Always active:

- Input gain
- Program lowpass
- Pre-emphasis
- MPX encoding
- Deviation scaling and limiting
- Output gain

Disabled by bypass:

- Wideband AGC
- HF trim
- Orbass
- Multiband processing
- Stereo widener

## Release build

Build a release app bundle / DMG:

```bash
./build-release.sh 0.8
```

Artifacts are written to `macOS/dist/`.

## References

- Standards PDFs and notes live in `documents/`
- Project-specific workflow guidance lives in `AGENTS.md`

## License

GPL-3.0. See `LICENSE`.
