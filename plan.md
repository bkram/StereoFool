# MPX Prime Roadmap

## Next up

1. **7.5 — FIR brick-wall 15 kHz.** Replace the Butterworth `encoderProgramLP` with a linear-phase FIR with >80 dB stop-band. Would push DC clipper aliasing from -38 dBFS to below -75 dBFS and improve stereo subcarrier separation. Design FIR at engine-start, cache coefficients. If latency exceeds monitor-path budget, keep the biquad LP on the monitor path.
2. **7.6 — Dynamic pre-emphasis ("Smart HF").** Lookahead-based HF envelope follower before pre-emphasis; dynamically relax the pre-emphasis curve during HF transients. Reduces clipper workload. Significant algorithm effort. **Must preserve M/S-domain pre-emphasis placement** (see 0.10 "Pre-emphasis placement" note below) — if a sidechain-only HF-boost feed into the pre-encode limiter is needed, build it as a dedicated sidechain path, not by moving pre-emphasis upstream.
3. **Preset tuning.** Make the composite clipper useful out of the box — current defaults (-3 dBFS threshold, -0.5 dBFS ceiling) don't engage meaningfully. Requires listening on real program material.
4. **Release smoke pass.** Validate live-apply vs restart-required settings on difficult real material.
5. **Extend baselines to `--verify-presets` and `--verify-long`.** Same `VerifierBaselineFile` schema, different scenario sets.

## Completed in 0.10

- **Stereotool-compatible RDS text grammar.** Fractional `Ns:`, `Nt:` transmit-count, `/` top-level separation, escape handling for `< > | : / \`, `||` word-wrap toggle (no-op), `<`/`>` scroll markers for PS with speed-by-repeat, `\F`/`\f` file-load aliases for `\R`/`\r`. See README "RDS text syntax". Pure parser extracted to `RDSTextParser.swift` with early-exit escape encode/decode.
- **4 PS banks with exclusive active selector.** `rdsPSA/B/C/D` + `rdsPSActiveBank`. Live-apply via `RDSRuntimeConfig` — switching active bank rebuilds `psSequence` without engine restart. INI migrates legacy `ps_dynamic` into bank A. Empty bank transmits 8 spaces.
- **Live RDS snapshot in Monitoring.** Monitoring card now reads the actual transmitted PS (8 chars, including live scroll window), RT (64/32), PTYN (8), Long PS (32) from the running coder — not a UI-side simulation. Writes guarded by `OSAllocatedUnfairLock` on the audio thread so UI contention never stalls the render callback.
- **macOS HIG polish.** Edit menu with Cut/Copy/Paste/Delete/Select All/Undo/Redo + Emoji & Symbols (⌃⌘Space) + Start Dictation. Close Window ⌘W. Start/Stop moved off ⌘T (system "New Tab") to ⌘Return. Scopes moved off ⌘0 (system "Actual Size") to ⇧⌘0. Ellipsis glyph `…` in menu titles. Settings window non-miniaturizable. UTType force-unwrap fix with fallback. Accessibility labels on icon-only controls; decorative icons marked `accessibilityHidden`. Semantic colors (`Color.gray` → `.secondary`). Dynamic Type on meter and spectrum readouts (fixed pixel sizes → `.caption2` / `.caption` with monospaced design).
- **57 tooltips (`.help`) across DSP controls.** AGC, Orbass, Parametric EQ, Multiband compressor + limiter + expander, Stereo Widener, Composite Limiter, Phase Rotator, Bass Clipper, DC Clipper, BS.412, Composite Clipper. Delivered via conditional `TooltipIfPresent` view modifier so rows without an explicit tooltip stay silent instead of clearing ambient help in the subtree.
- **95+ new tests across 8 files.** `RDSTextParserTests` (21), `RDSTextOrchestrationTests` (26), `RDSAdvanceTests` (10), `RDSSignalTests` (9, spectral FFT tests on composite output), `RDSBitstreamTests` (16, decodes emitted 104-bit groups and verifies CRCs / PI / group type / segment / AB flag / Nt: advance / PS scroll end-to-end), `PSBankTests` (12), `DSPThroughputTests` (4, real-time-budget regression tests, see below). 118 / 11 suites green.
- **DSP throughput regression suite.** Wall-clock cost of the full chain on HF-rich stereo measured against the bypass baseline. Catches the class of regression that triggered the 0.10 dropout scare: any stage whose per-sample cost suddenly jumps 2-3× (limiter fighting upstream HF boost, filter gone memoryless+oversampled without planning for it, etc.) fails `fullChainInsideRelativeBudget`. `preEmphasisDoesNotExplodeFullChainCost` pins the exact `b806053` pattern.
- **RT dynamic-sequence cache.** `currentRTFrame` was calling `parseTimedSequence` on every `buildGroup2` (~6×/sec on the audio thread) even when the RT text hadn't changed. Now caches by `(signature, limit, centered)`, and additionally skips `expandNowPlayingMacros` (DateFormatter + string replacements) when the snapshot revision, minute epoch, and day epoch all match the cached values. `RDSTextParser.decodeEscapes` early-returns on inputs with no sentinel characters (the 99%+ case).

## Open gaps

1. **Calibration workflow** — monitoring card shows deviation/pilot/RDS/margin, but exciter-facing guidance and operational long-run use need more hardening.
2. **AGC validation** — wideband AGC defaults and range need broader validation against the current final stage on real program.
3. **Stereo image validation** — mono bass, widener, Orbass, and multiband interactions need preset-level validation on difficult real program. Width behavior still needs broader validation.
4. **Live-apply boundaries** — live DSP updates work, but need a smoke-test pass to verify no transient artifacts and that restart-only boundaries stay obvious.
5. ~~**RDS text syntax** — missing: `Nt:` transmit-count segments, escape handling, optional wrap markers, clearer documented grammar.~~ Done 2026-04-19 in 0.10.

## Phase 7 — remaining items

### 7.5. FIR brick-wall 15 kHz
See "Next up" #1.

### 7.6. Dynamic pre-emphasis
See "Next up" #2. **Constraint:** must stay in M/S domain inside `makeCompositeComponents`, or implement as a dedicated sidechain feed into the pre-encode limiter. Moving the audio-path pre-emphasis upstream of the limiter (the `b806053` pattern) is verified to cause ring-overflow dropouts and is now guarded by `DSPThroughputTests.preEmphasisDoesNotExplodeFullChainCost`.

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
4. ~~Expand the Swift Testing suite into MPX generation, filters, AGC, and config round-trip coverage.~~ Partially done in 0.10 — RDS coverage is strong now (parser, orchestration, advance, bitstream, signal, PS banks). Still to add: AGC / filter-primitive unit tests, `AppConfig` round-trip and invalid-input tests.
5. Split the monolithic SwiftUI view model into smaller focused view models.
6. Loosen tight coupling between engine and generator; add DI seams for system-facing services.
7. Harden config file watching/reload behavior against race conditions.
8. ~~Move remaining non-DSP work off the audio callback (RDS string preparation still on render path).~~ Partially done in 0.10 — `currentRTFrame` caches the parsed dynamic sequence and skips `expandNowPlayingMacros` when inputs are stable. Remaining: RDS byte-string preparation is still done on the render path.

## Code-quality priorities

### P0 — Confidence and safety
1. ~~Add deterministic unit tests for major DSP primitives (filters, limiters, stereo coding, pilot/RDS, AGC, bypass paths).~~ Partially done in 0.10 — RDS coverage comprehensive (parser + orchestration + signal spectrum + bitstream + advance + PS banks + throughput = 95+ tests). Still to add: AGC envelope behavior, filter primitives (PreemphasisFilter, DeemphasisFilter, Biquad, BiquadCascade6), stereo coding M/S round-trip sanity, bypass-path null-signal tests.
2. Fix the verifier bandwidth metric so RDS does not produce misleading occupied-width failures (`bright_dense` occ999 warning disappears when `en_rds = False`).
3. Add config round-trip and invalid-input tests for `AppConfig`.
4. Define and test live-apply vs restart-required behavior as code, not just UI guidance.

### P1 — Structural cleanup
1. Split `MPXGenerator.swift` (~6300 lines now) into stage-focused components.
2. Split `AudioOutputEngine.swift` by concern (device routing, capture, render loop, metering, monitoring).
3. Split `SwiftUIControlApp.swift` (~7200 lines now) into smaller views and state holders.
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

## Pre-emphasis placement (process note)

Commit `b806053` on the path from 0.9 → 0.10 relocated pre-emphasis from M/S domain (inside `makeCompositeComponents`, 2 filter passes on M and S) to L/R domain (upstream of the pre-encode limiter in `processSampleDetailed`, still 2 filter passes but feeding the limiter a signal with a 10–12 dB HF boost). The motivation was reasonable — let the pre-encode limiter peak-control the pre-emphasized signal — but the side effect was that the limiter ran in near-continuous gain reduction on HF-rich program. Combined per-sample cost on the audio thread exceeded the real-time budget, causing the input ring to fill from empty to capacity (~1.35 s) within 3–5 s of every engine start.

**Resolution:** 0.10 branches directly from `9747de3` (the commit before `b806053`) and skips the relocation. Pre-emphasis remains in M/S. The `DSPThroughputTests.preEmphasisDoesNotExplodeFullChainCost` test guards against reintroducing the pattern.

**If dynamic pre-emphasis (7.6) ever wants peak-control of the boosted signal:** build a dedicated sidechain — compute an HF-emphasized version as the limiter's detector input while keeping the audio path in M/S — rather than moving the audio-domain filter upstream.

## Design constraints

- Keep realtime callbacks lock-free and allocation-free. Snapshot writes use `OSAllocatedUnfairLock` (priority-inheriting) — any new audio-thread cross-thread communication must use the same primitive or an atomic, never `NSLock`.
- Do not move shell/file/network work into DSP paths.
- Preserve integrated RDS and monitoring workflow.
- Keep monitor-output latency separate from transmit-path quality.
- Pre-emphasis stays in M/S inside `makeCompositeComponents`. Enforced by `DSPThroughputTests`.

## References

- [Omnia.9 MPX setup](https://docs.telosalliance.com/docs/setting-up-omnia9-for-fm-pre-emph-output-via-aesebu)
- [Omnia Direct MPX-over-AES](https://docs.telosalliance.com/docs/using-mpx-over-aes-omnia-direct-on-the-omnia9)
- [Telos RDS guidance](https://docs.telosalliance.com/docs/rds)
- [Orban 8700i specs](https://www.orban.com/specifications-optimod8700i)
- [Orban 8700i features](https://www.orban.com/keyfeatures-optimod8700i)
- [Stereotool FM transmitter](https://www.thimeo.com/documentation/fm-transmitter.html)
- [Stereotool limiting/clipping](https://help.stereotool.com/7.40/limiting_and_clipping.shtml)
- [BreakawayOne](https://www.breakawaysoftware.com/breakawayone)
