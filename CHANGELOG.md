# Changelog

## 0.6

- Added DSP/web process isolation: audio engine now runs in a dedicated worker process with command/telemetry IPC.
- Allowlist behavior fixed: configured `allow_subnets` are additive, while localhost (`127.0.0.0/8`, `::1/128`) remains always allowed.
- Monitoring scopes now use fixed-size canvases with centered layout for consistent rendering.
- Monitoring meters now use faster ballistic bar updates plus configurable sticky peak hold/fall and reset controls.
- UI parameter updates are now coalesced and applied on a fixed DSP control tick to reduce live-update churn under heavy web activity.
- Added `Orbass`: adaptive low-end enhancement with harmonic bass support, inserted before multiband in the DSP chain.
- Added built-in multiband genre presets (3-band and 5-band) for one-click baseline tuning.
- Added multiband preset intensity trim (`Light` / `Normal` / `Heavy`) for faster coarse tuning.
- Lookahead limiter path upgraded to true delayed lookahead processing with per-stage sample-rate-correct timing.
- Multiband crossover network rebuilt around LR4 low-pass stages with complementary remainder splitting to keep unity recombination and reduce tonal/level drift.
- Dynamics startup behavior hardened: AGC and multiband detector envelopes now warm-start from program level to avoid loud-then-soft settling.
- Multiband dynamics upgraded with soft-knee compression, optional program-dependent release scaling, and cross-band envelope linking for steadier spectral loudness.
- Added Processing UI controls for multiband knee, band-link strength, and program-dependent release.
- Genre presets now include tuned advanced multiband defaults (knee/link/release behavior) per format.
- Fixed multiband detector timing at high sample rates by correcting attack/release coefficients for control-rate decimation; reduced release-scaling range to prevent long-term level sag.
- Rebuilt multiband compression around a feed-forward dB-domain model (RMS-linked detector, soft-knee gain computer, attack/release gain-reduction ballistics, and linked sidechain control) to eliminate long-run fade behavior.
- Upgraded multiband sidechain/dynamics to enterprise-style behavior with persistent true-RMS detector memory per band and dual-stage program-dependent release ballistics (fast+slow blend).
- Retuned 3-band/5-band multiband presets and baseline defaults toward broadcast-style processing (higher band-link, smoother knee, slower LF recovery) for behavior closer to enterprise processors.
- Hardened separate-input fallback path with adaptive clock-drift correction and hold-last-sample underrun fill, reducing long-run level dropouts when input/output devices are not clock-locked.
- Pre-emphasis drive guard is now only active with explicit pre-emphasis limiting enabled; this prevents hidden long-run level riding when protection stages are disabled.
- Absolute full-scale safety handling no longer applies slow gain riding when optional protection is off; it now uses direct hard clipping as a transparent last-resort guard against runaway fades.
- Startup/runtime flow refactored around `main()` helpers and worker lifecycle supervision.
- Restored CLI `--length` capture-complete auto-exit behavior and removed legacy in-process audio runtime path from web app.
- Version and docs updated to 0.6.
- DSP processing order aligned closer to broadcast processor flow with explicit audio-domain staging and MPX-domain finishing.
- Added wideband AGC stage and pre-emphasis-aware HF control stage with persistent runtime parameters.
- Protection path updated for smoother behavior: linked sum/diff lookahead control, separate pre-emphasis limiter oversample state per path, and softer headroom gain attack.
- MPX cleanup placement corrected: DC block and notch now run in MPX-audio path before pilot/RDS injection.
- Help tab signal-chain documentation updated to match runtime processing order.
- Auth expiry UX improved: monitor snapshot/settings `401` now redirect the UI to `/login`, including socket connect-auth failures.
- Added `Audio Priority Profile` in Interfaces (`normal`, `high`, `realtime-attempt`) with macOS worker/audio-thread priority application and safe fallback logging.

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
  - monitoring scopes now use fixed-size canvases with centered layout for consistent rendering and lower browser draw cost.
- Websocket/reload resilience:
  - monitor emits target authenticated monitor clients only.
  - reconnect handling replaces stale session sockets to reduce rapid-refresh churn.
  - monitor payload loop skips work when no UI clients are connected.
  - added `/monitor_snapshot` authenticated JSON endpoint and frontend fallback polling when websocket monitor frames stall.
  - web runtime standardized on Flask-SocketIO `threading` mode for consistent UI behavior.
- Host API and interface robustness:
  - `STEREOFOOL_HOSTAPI` now supports alias matching (`wasapi`, `wdmks`, etc.) with strict override behavior.
  - startup still normalizes stale device indices to valid devices.
  - monitor/device labels in monitoring view corrected.
- Config persistence reliability:
  - debounced config writes added for UI updates.
  - config write path serialized and hardened against writer-thread failure.
- Startup/runtime structure:
  - startup flow refactored into `main()` with focused helpers for CLI parsing, config bootstrap, device logging, and server launch.
  - config bootstrap now uses `pathlib.Path` for clearer file handling.
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
