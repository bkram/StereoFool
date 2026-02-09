# Changelog

## 0.5

- Audio callback and UI contention reduced:
  - moved meter/scope aggregation off the callback path into a telemetry worker.
  - optimized callback allocations and hot-path math for lower CPU usage.
  - added cached template rendering and UI cache invalidation to reduce reload overhead.
- Buffering and contention hardening:
  - configurable `INTERFACES.blocksize` integrated into runtime and UI (Interfaces > Audio Engine).
  - monitor output now uses prefill/rebuffer behavior to reduce underrun artifacts.
  - input fallback reader now trims backlog to keep latency bounded under CPU spikes.
- Monitor/output safety:
  - when monitor output device matches MPX output device, MPX output is auto-disabled for that run.
  - monitor UI fields now keep fixed placeholders and no longer collapse when empty.
- Websocket/reload resilience:
  - monitor emits target authenticated monitor clients only.
  - reconnect handling replaces stale session sockets to reduce rapid-refresh churn.
  - monitor payload loop skips work when no UI clients are connected.
- Host API and interface robustness:
  - `STEREOFOOL_HOSTAPI` now supports alias matching (`wasapi`, `wdmks`, etc.) with strict override behavior.
  - startup still normalizes stale device indices to valid devices.
  - monitor/device labels in monitoring view corrected.
- Config persistence reliability:
  - debounced config writes added for UI updates.
  - config write path serialized and hardened against writer-thread failure.
- Diagnostics:
  - added periodic and final totals for stream status flags (underflow/overflow/priming).
  - added monitor queue drop/underrun counters and input backlog trim counters.
- Widener behavior:
  - level compensation changed to static mix compensation to avoid gain pumping artifacts.
- Documentation:
  - README updated to version 0.5 and expanded with Windows PortAudio binary instructions.
  - README now includes buffering guidance and notes that rapid browser refresh can still cause brief glitches in single-process mode.
  - Help text aligned with current DSP chain.

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
