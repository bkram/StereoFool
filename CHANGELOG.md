# Changelog

## 0.85

### Added
- Configurable now-playing script support in the RDS Radiotext section with native file picker, poll interval, timeout, and runtime status display
- Radiotext macro expansion for now-playing metadata: `{now_playing}`, `{display}`, `{artist}`, and `{title}`
- Additional Radiotext template macros: `{date}` and `{time}`
- README documentation for the expected now-playing script output format and RT/RT+ configuration
- Broadcast preset picker for the final MPX stage: `Balanced Music`, `CHR / Dance`, `Punchy Music`, and `Speech / Talk`
- Final-stage limiter telemetry in Monitoring and DSP Overview showing live and held gain reduction
- Composite calibration telemetry showing pilot %, RDS %, audio-composite peak, budget margin, and a `Safe` / `Tight` / `Risk` composite-budget state
- Dedicated `Mono Bass` stage with configurable crossover in the Widener tab
- Orbass preset/config wiring for density and subharmonics, with the adaptive Orbass path now active in the live DSP chain
- Offline MPX verification mode with deterministic scenarios and exit codes
- Long-run compliance/regression verification mode:
  - `--verify-long`
  - focused on `program_mix`, `bright_dense`, `vocal_sibilant`, `transient_push`, and `wide_bass`
- Additional audible-quality verification scenarios:
  - `bright_dense`
  - `vocal_sibilant`
  - `transient_push`
  - `wide_bass`
- Preset-sweep verification mode:
  - `--verify-presets`
  - focused on `5B AC/Pop`, `5B CHR/EDM`, `5B Rock`, `5B Talk`, `5B News`, `5B Urban`, and `5B Dance`
- Window frame persistence for the main window and utility windows

### Fixed
- RT+ tagging now uses structured now-playing metadata more reliably for artist/title extraction
- RT+ tag ordering now follows the field positions in transmitted radiotext
- Now-playing script failures and empty output now clear the active metadata, show a friendly `No Song Data` status, and discard the affected RT segment instead of leaving blank labels behind
- `output_gain_db` and `limit_mpx` are now active in the final render path
- Added a proper `Final Drive` stage ahead of composite limiting and improved composite limiter behavior
- `Mono Mode` now suppresses pilot, stereo subcarrier, and RDS so it behaves as a true mono composite mode
- Final drive now affects the audio-composite path without dragging pilot and RDS injection levels along with it
- The main composite limiter now runs before pilot/RDS sum, with the full-MPX limiter acting as a safety stage
- Stereo widener no longer behaves as a raw full-band M/S gain stage and now includes stereo-image protection
- Orbass was retuned to be substantially more conservative and less artifact-prone
- Multiband now uses complementary Linkwitz-Riley crossover stages instead of one-pole residual splits
- Multiband defaults and presets were retuned toward more realistic broadcast-style starting points
- `5B AC/Pop`, `5B CHR/EDM`, `5B Rock`, `5B Talk`, `5B News`, `5B Urban`, and `5B Dance` were tuned and verified against the focused preset sweep
- MPX width/compliance is now explicitly verifier-backed with encoder-side bandwidth guarding and a dynamic HF compliance guard ahead of stereo encode/pre-emphasis
- Processing and RDS reset buttons now only reset the active tab
- External config reloads now correctly preserve pending apply state

## 0.8

### Added
- Multiband dynamics presets (CHR/EDM, Rock, AC/Pop, Country, Talk, Urban, Dance, News, Jazz, Classical) with intensity control (Light/Normal/Heavy)
- FFT spectrum window toggle (96 kHz full / 60 kHz FM band)
- Reset Processing to Defaults button
- Default PTY set to Science
- Native MPX Prime app icon assets for runtime and release builds

### Changed
- Updated default RDS text to "MPX Prime: FM MPX + RDS Audio Processor"
- Unified window sizes for Scopes, Spectrum, and Levels windows (700x500, min 600x450)
- Processing section refactored with HIG-compliant plain Section style
- MPX spectrum display simplified (removed 19 kHz pilot marker)
- Window size constants centralized for easy configuration
- Main navigation reduced to Monitoring, Processing, and RDS; app-level controls moved into Settings
- Default config path changed to `~/Library/Application Support/MPX Prime/MPX Prime.ini`
- Default program lowpass changed to `16.4 kHz`
- Monitoring view and Settings were updated for more native macOS behavior and layout

### Fixed
- Level meters now properly displayed in Levels window
- Removed duplicate state variables in Processing section
- Main window close behavior now keeps the app running and supports reopen from Dock / Window menu

## 0.7

- Initial native macOS release built with Swift + SwiftUI.
- Real-time MPX generation using AVAudioEngine with AVAudioSourceNode.
- Input capture via AVAudioEngine input tap with ring buffer.
- Native macOS UI with SwiftUI sidebar navigation and monitoring dashboard.
- Phase-coherent stereo encoder with 19 kHz pilot and 38 kHz DSB-SC subcarrier.
- RDS encoding with EN 50067 biphase shaping and 57 kHz subcarrier.
- DSP features: input gain, wideband AGC, Orbass bass enhancement, multiband compression, stereo widener.
- Pre-emphasis support (0/50/75 µs) with HF trim control.
- Lookahead limiter for MPX protection.
- Lock-free real-time audio path with pre-allocated buffers.
- vDSP-accelerated metering for scope display.
