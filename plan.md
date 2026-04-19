# MPX Prime Roadmap

## Next up

1. **7.5 — FIR brick-wall 15 kHz.** Replace the Butterworth `encoderProgramLP` with a linear-phase FIR with >80 dB stop-band. Would push DC clipper aliasing from -38 dBFS to below -75 dBFS and improve stereo subcarrier separation. Design FIR at engine-start, cache coefficients. If latency exceeds monitor-path budget, keep the biquad LP on the monitor path.
2. **7.6 — Dynamic pre-emphasis ("Smart HF").** Lookahead-based HF envelope follower before pre-emphasis; dynamically relax the pre-emphasis curve during HF transients. Reduces clipper workload. Significant algorithm effort.
3. **Preset tuning.** Make the composite clipper useful out of the box — current defaults (-3 dBFS threshold, -0.5 dBFS ceiling) don't engage meaningfully. Requires listening on real program material.
4. **Release smoke pass.** Validate live-apply vs restart-required settings on difficult real material.
5. **Extend baselines to `--verify-presets` and `--verify-long`.** Same `VerifierBaselineFile` schema, different scenario sets.

## Open gaps

1. **Calibration workflow** — monitoring card shows deviation/pilot/RDS/margin, but exciter-facing guidance and operational long-run use need more hardening.
2. **AGC validation** — wideband AGC defaults and range need broader validation against the current final stage on real program.
3. **Stereo image validation** — mono bass, widener, Orbass, and multiband interactions need preset-level validation on difficult real program. Width behavior still needs broader validation.
4. **Live-apply boundaries** — live DSP updates work, but need a smoke-test pass to verify no transient artifacts and that restart-only boundaries stay obvious.
5. ~~**RDS text syntax** — missing: `Nt:` transmit-count segments, escape handling, optional wrap markers, clearer documented grammar.~~ Done 2026-04-19: Stereotool-compatible grammar (fractional `Ns:`, `Nt:`, escapes, `||`, `<`/`>` scroll for PS, `\F`/`\f` aliases). See README "RDS text syntax".

## Phase 7 — remaining items

### 7.5. FIR brick-wall 15 kHz
See "Next up" #1.

### 7.6. Dynamic pre-emphasis
See "Next up" #2.

### 7.7. Pilot-synchronized limiter control
Defer until measurement justifies. If the composite limiter's control envelope modulates near 19 kHz, it can induce sidebands around the pilot. Measure first, then phase-lock the limiter's release to a pilot subharmonic if needed.

### 7.9. Input-side restoration
Defer. Declipper / dehumfilter / delossifier are genuinely complex algorithms. Only justified if MPX Prime starts being used for degraded streaming sources.

## Tactical backlog

### Release-blocking
1. Smoke-test pass for live-apply vs restart-required settings.

### Sprint
1. Validate Orbass, mono bass, widener, and multiband interaction on difficult real material.
2. Refine calibration workflow only where real operator friction exists.
3. Tune composite clipper defaults for a useful starting point.

### Medium-term
1. Reduce duplicated filter configuration logic in biquad/crossover helpers.
2. Replace undocumented DSP magic numbers with named constants.
3. Simplify and test RDS group scheduler modes more deterministically.
4. Expand the Swift Testing suite into MPX generation, filters, AGC, and config round-trip coverage.
5. Split the monolithic SwiftUI view model into smaller focused view models.
6. Loosen tight coupling between engine and generator; add DI seams for system-facing services.
7. Harden config file watching/reload behavior against race conditions.
8. Move remaining non-DSP work off the audio callback (RDS string preparation still on render path).

## Code-quality priorities

### P0 — Confidence and safety
1. Add deterministic unit tests for major DSP primitives (filters, limiters, stereo coding, pilot/RDS, AGC, bypass paths).
2. Fix the verifier bandwidth metric so RDS does not produce misleading occupied-width failures (`bright_dense` occ999 warning disappears when `en_rds = False`).
3. Add config round-trip and invalid-input tests for `AppConfig`.
4. Define and test live-apply vs restart-required behavior as code, not just UI guidance.

### P1 — Structural cleanup
1. Split `MPXGenerator.swift` (~6200 lines) into stage-focused components.
2. Split `AudioOutputEngine.swift` by concern (device routing, capture, render loop, metering, monitoring).
3. Split `SwiftUIControlApp.swift` (~6800 lines) into smaller views and state holders.
4. Reduce hidden coupling between engine, config, generator, and UI state.

### P2 — Harden behavior
1. Strengthen `AppConfig` validation (invalid ranges, illegal combinations, impossible sample-rate/block-size).
2. Re-tune final-stage composite headroom for vocal/transient stability (`sum_level` 1.0 → 0.9 investigation).
3. Harden device and routing edge cases.
4. Make error reporting more structured.

### P3 — Performance
1. Further vDSP utilization where profiling shows value.
2. Cache RDS byte preparation to avoid repeated string allocations.
3. Add benchmarks for the hottest paths.
4. Capture baseline Instruments data and keep it current.

## Design constraints

- Keep realtime callbacks lock-free and allocation-free.
- Do not move shell/file/network work into DSP paths.
- Preserve integrated RDS and monitoring workflow.
- Keep monitor-output latency separate from transmit-path quality.

## References

- [Omnia.9 MPX setup](https://docs.telosalliance.com/docs/setting-up-omnia9-for-fm-pre-emph-output-via-aesebu)
- [Omnia Direct MPX-over-AES](https://docs.telosalliance.com/docs/using-mpx-over-aes-omnia-direct-on-the-omnia9)
- [Telos RDS guidance](https://docs.telosalliance.com/docs/rds)
- [Orban 8700i specs](https://www.orban.com/specifications-optimod8700i)
- [Orban 8700i features](https://www.orban.com/keyfeatures-optimod8700i)
- [Stereotool FM transmitter](https://www.thimeo.com/documentation/fm-transmitter.html)
- [Stereotool limiting/clipping](https://help.stereotool.com/7.40/limiting_and_clipping.shtml)
- [BreakawayOne](https://www.breakawaysoftware.com/breakawayone)
