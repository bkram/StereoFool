# Changelog

## 0.5

- Windows audio host API preference now favors DirectSound (MME remains available).
- Startup now normalizes saved device indices to valid devices, avoiding bad/stale selections.
- RDS default strings synced with shipped `stereofool.ini`.
- Monitoring device labels/values swapped.
- README: added a Windows note about launching with higher priority on low-end systems.
- Help tab updated to match the current DSP chain order.

## 0.4

- Removed AGC and input limiter from the processing chain and UI.
- Multiband now uses SimpleMultiBandComp-style band split and JUCE-style compressor behavior; per-band controls added.
- Added Airwindows Wider-based stereo widener and controls.
- Added processing bypass button to run stereo+RDS without processing blocks.
- Added optional monitor audio output (demodulated stereo) with device selection.
- Updated monitoring panel layout and meters (L/R input meters, limiter grouping).
- UI Processing tab reorganized into signal-flow cards.
- Composite LPF removed.
- Documentation updates (README, ARCHITECTURE, attributions).

## 0.3

- Interfaces tab now includes input/output gain and MPX capture controls.
- MPX monitoring adds a modulation meter in kHz plus interface/sample rate readouts.
- RDS deviation is now calibrated in kHz (EN 50067 target 2.0 kHz).
- Added WAV capture + analyzer workflow for calibration and QA.
- Removed network stream source support.
- Levels tab split into Composite/Pilot/RDS cards with 100 kHz max and standards note.
- RDS tab layout tightened (RT+ format grouping, consistent spacing, updated labels).
- Settings tab reordered with Network Access first and stacked vertically.
- About tab added and Settings moved to last in navigation.
- CSS/JS extracted to static files with unified input styling and neutral subheaders.
