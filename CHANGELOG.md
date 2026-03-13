# Changelog

## 0.8

### Added
- Multiband dynamics presets (CHR/EDM, Rock, AC/Pop, Country, Talk, Urban, Dance, News, Jazz, Classical) with intensity control (Light/Normal/Heavy)
- FFT spectrum window toggle (96 kHz full / 60 kHz FM band)
- Reset Processing to Defaults button
- Default PTY set to Science
- Native StereoFool app icon assets for runtime and release builds

### Changed
- Updated default RDS text to "StereoFool: FM MPX + RDS Audio Processor"
- Unified window sizes for Scopes, Spectrum, and Levels windows (700x500, min 600x450)
- Processing section refactored with HIG-compliant plain Section style
- MPX spectrum display simplified (removed 19 kHz pilot marker)
- Window size constants centralized for easy configuration
- Main navigation reduced to Monitoring, Processing, and RDS; app-level controls moved into Settings
- Default config path changed to `~/Library/Application Support/StereoFool/StereoFool.ini`
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
