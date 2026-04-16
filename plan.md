# MPX Prime FM/MPX Roadmap

## What MPX Prime is

MPX Prime is a native macOS FM composite (MPX) generator written in Swift and SwiftUI. It takes live audio input or a test tone, applies optional broadcast-style processing, generates stereo FM baseband with 19 kHz pilot and optional 57 kHz RDS, and sends MPX (plus an optional decoded monitor signal) to Core Audio devices.

## Goal

Bring MPX Prime closer to a broadcast-grade FM composite generator and processor by:

- fixing current gain-structure bugs
- separating operating-level control from output calibration
- moving final loudness control into the composite/MPX domain
- preserving pilot and RDS integrity under loudness processing
- improving calibration, metering, and verification

This plan is based on current MPX Prime behavior plus publicly available official material from Telos/Omnia, Orban, Stereo Tool, and Breakaway.

## Current strengths

Items worth preserving when refactoring — the roadmap is additive, not a rewrite.

- Clear separation of concerns across SwiftUI app / engine / generator
- Feature breadth matches professional FM processors (stereo encoding, RDS, calibration, verifier, preset sweep)
- Real-time audio pipeline: lock-free ring buffer, allocation-free render callback, Accelerate-backed metering
- Comprehensive offline verification harness with preset sweep and long-run mode
- FFT/spectrum scratch buffers cached; only rebuilt on size change
- Modern Swift (Combine, atomics, async/await at the edges)

## Research summary

### Enterprise processor patterns

Official Omnia/Telos and Orban material shows a consistent FM architecture:

- integrated stereo and RDS generation inside the processor is preferred because final loudness control can then happen in the composite domain
- composite-domain limiting/clipping is used to recover headroom that is lost when you clip audio before adding pilot, stereo subcarrier, and RDS
- MPX/composite output is treated as a calibrated output, separate from upstream gain-riding behavior
- pre-emphasis should exist in exactly one place
- pilot and RDS injection are calibrated, not incidental
- high-rate internal or output MPX handling is standard

### Stereo Tool observations

Stereo Tool is the clearest public software reference for modern MPX generation behavior:

- FM processing is treated as a dedicated subsystem, not a minor add-on
- composite clipping is explicitly described as a major loudness advantage versus clipping audio before stereo/RDS generation
- oversampling is treated as important for MPX generation and clipping quality
- pilot and RDS levels are exposed as calibrated percentages
- BS.412 / spectrum compliance and RF-spectrum visualization are part of the FM toolset

Takeaway for MPX Prime:

- if we want competitive FM loudness and cleanliness, final loudness control must move into an oversampled composite stage
- RF/compliance visibility should eventually be first-class, not an afterthought

### Breakaway observations

BreakawayOne's official public material is less detailed about internal FM/MPX mechanics, but it does confirm:

- FM-specific cores exist as a distinct product mode
- BS.412 support matters enough to be a product-level feature
- "back-end peak control" is a key design element
- RDS is modular and considered part of the FM ecosystem
- a separate low-latency monitor path is useful operationally

Takeaway for MPX Prime:

- treat FM as a dedicated processing/output topology
- keep low-latency monitoring as a separate design concern from the highest-quality transmit path
- make peak control at the back end a central component, not a side effect

### Limits of public research

Breakaway does not appear to publish the same level of public technical detail about its composite clipping path that Stereo Tool, Omnia, and Orban do. We should not infer exact internal algorithms from marketing copy alone.

## Current open gaps

### 1. Pilot/RDS calibration workflow exists, but still needs exciter-facing polish

Monitoring now has a dedicated calibration workflow with pilot, RDS, audio-composite peak, budget margin, deviation, and safety-limiter visibility. The remaining gap is making it even more explicit for real exciter alignment and longer operational use.

Impact:

- day-to-day calibration is much clearer than before
- exciter integration and calibration guidance still need more hardening than a status card alone

### 2. AGC still needs more validation against the current final stage

Wideband AGC is now behaving more like a platform leveler, but its defaults and range still need broader validation against the current final stage.

### 3. Stereo enhancement still needs deeper validation

MPX Prime now has a more professional stereo-image path, image presets, and a history view, but it still needs deliberate listening and measurement work.

Impact:

- mono bass, widener, Orbass, and multiband interactions still need preset-level validation
- stereo history now exists, but compliance-style validation on difficult real program is still limited
- width behavior still needs broader validation on difficult real program

### 4. Runtime apply boundaries are much better, but still need validation discipline

MPX Prime now applies most ordinary DSP controls live and reserves restart-only handling for engine, routing, and encoder-structure changes. That is the right model, but it still needs stronger validation so live updates do not introduce transient artifacts and restart-only boundaries stay obvious.

Impact:

- live DSP updates are now usable during operation, which is a major workflow improvement
- the remaining restart-required settings are much clearer in the UI, but still need broader smoke testing
- parameter-apply behavior now deserves explicit testing instead of being treated as incidental UI plumbing

### 5. Verification is strong, but coverage is still limited

The offline verifier, preset sweep, width/compliance checks, and long-run mode now exist, but:

- long-run coverage is still short and focused rather than broad and archival
- there is no stored golden-baseline artifact beyond the current in-code signature
- compliance-style analysis is still lighter than a true RF toolchain

### 6. Swift DSP implementation still has cleanup debt

MPX Prime's Swift DSP is now credible and effective, but there are still implementation-level loose ends that should be addressed before treating the chain as fully mature.

Loose ends:

- widener, mono bass, Orbass, and multiband interaction still needs broader preset-level validation on real program material beyond the current focused sweep
- pilot/RDS/headroom telemetry exists, but there is still no explicit deviation estimator or exciter-calibration workflow
- RDS string preparation work that should move further off the render path

Practical implication:

- the Swift DSP core is strong enough to continue building on directly
- the next quality gains come from cleanup, validation, and measurement discipline rather than from rewriting out of Swift
- the final composite stage is sensitive enough that even a structural refactor can change output measurably, so all cleanup there must be verification-backed and incremental

### 7. RDS text syntax is functional, but still behind established tooling

MPX Prime already supports timed PS/RT sequences such as `10s:Text/10s:Other Text`, but it does not yet match the more mature public user-facing syntax that processors such as Stereo Tool expose.

What MPX Prime already supports:

- timed text segments with `Ns:Text`
- slash-separated PS and RT sequences
- now-playing macro expansion for RT

Useful compatibility work that can be implemented clean-room from public documentation:

- transmit-count syntax such as `Nt:Text`
- escape handling for literal separators and control characters
- optional word-wrap control markers
- a clearer documented grammar for timed/dynamic PS and RT text
- keep RDS code-page handling deterministic for supported Latin characters and graceful for unsupported ones

Constraints:

- this should be implemented from public documentation only
- do not rely on reverse engineering or copied parser behavior
- preserve MPX Prime-specific macro support (`{artist}`, `{title}`, `{date}`, `{time}`, etc.)

### 8. Oversampling strategy and commercial-grade clipping are not yet at par

MPX Prime's topology matches public material from Omnia, Orban, Stereotool, and BreakawayOne, but the algorithms *inside* that topology are a mix of professional-grade and simplified. The biggest single gap is oversampling around the nonlinearities: the distortion-cancelled clipper and bass clipper both run at native sample rate. Their `tanh` generates harmonics above Nyquist that alias straight back into the audio band, and the LP-filtered error-subtract cancels LF IMD without addressing HF aliasing.

A secondary gap is that the composite stage is a *true-peak limiter*, not a *composite clipper*. Commercial processors use a distortion-shaped, heavily-oversampled composite clipper as the main loudness lever (Orban's half-cosine-interpolated, Omnia's Bass/Composite Tools, Stereotool's iterative HDC). MPX Prime's current composite stage will hit peak targets, but will not deliver the same subjective loudness density at the same deviation.

See Phase 7 in the implementation plan below for the concrete gap-closing work.

## Target architecture

### Current FM chain

This matches what the generator actually runs today. All optional stages are disabled by default. See `ARCHITECTURE.md` for the authoritative ordered list.

1. Input trim / source conditioning (input gain + mono fold)
2. Phase rotation (4-pole allpass, optional)
3. Wideband AGC gain rider
4. Input HPF + program lowpass
5. HF trim + 4-band parametric EQ (optional)
6. Orbass + mono-bass + stereo widener
7. Multiband compressor (3- or 5-band LR4) with optional per-band downward expander and per-band fast limiter
8. Bass clipper (LR4 split + tanh, optional)
9. Distortion-cancelled clipper (Orban-style LF cancellation, optional)
10. Encoder HF guard + encoder program lowpass (~15 kHz)
11. Stereo-image protection
12. Pre-encode audio limiter (L/R domain, stereo-linked true-peak)
13. Stereo encoder with pre-emphasis (M/S, 38 kHz DSB-SC subcarrier)
14. Audio-composite limiter (4× oversampled true-peak)
15. BS.412 MPX power limiter (optional, EU compliance)
16. Safety limiter (audio composite only — no pilot, no RDS)
17. Pilot and RDS injection (post-limiter, constant amplitude)
18. MPX output calibration trim
19. Hardware output

The two-stage limiter architecture (steps 12 + 14) follows Omnia/Orban/Stereotool practice: the pre-encode limiter does primary peak control in the L/R domain before pre-emphasis amplifies peaks further, while the composite limiter catches overshoots from stereo encoding. Pilot and RDS bypass all limiting stages entirely (step 17) so receivers always see constant-amplitude reference signals.

### Control separation

MPX Prime should clearly distinguish:

- `Input Gain`: source trim
- `Wideband AGC Target`: average operating platform
- `Final Drive`: how hard we hit final loudness protection
- `MPX Output Level` or `Output Calibration`: output alignment to exciter / sound card / deviation target

Users should not need to abuse AGC target to get acceptable loudness.

## Implementation plan

### Phase 1. Fix the gain structure

Status: mostly complete

Still open:

1. Add one internal gain-structure note per stage in code comments so future tuning stays coherent.

### Phase 2. Add a proper final composite stage

Status: complete. See `ARCHITECTURE.md` for the architecture. Follow-ups that live on:

1. Strengthen long-run width/compliance regression checks beyond the current focused mode.
2. Move from in-code signature checks toward stored baseline artifacts if they prove useful.

Success criteria:

- higher subjective loudness without excessive HF splatter
- output still respects configured deviation targets
- bright/dense material stays inside the explicit verifier width/compliance envelope
- structural cleanup of the final stage does not change verifier output unless intentionally retuned

### Phase 3. Calibrate pilot, RDS, and MPX headroom

Status: in progress

Next work:

1. Revisit defaults for:
   - pilot injection
   - RDS injection
   - composite headroom
2. Document expected exciter integration:
   - when MPX Prime pre-emphasis is on, external pre-emphasis must be off
3. Keep refining the dedicated calibration workflow with clearer exciter-facing guidance and warning states if needed.

Success criteria:

- defaults are sane without requiring guesswork
- users can see whether the chain is calibrated rather than just "loud"

### Phase 4. Validate stereo image, mono bass, and Orbass interaction

Status: in progress

Next work:

1. Validate mono compatibility and low-end stability on difficult program material.
2. Retune or expand image presets only when new listening or verifier evidence justifies it.

Success criteria:

- bass stays centered and stable on-air
- width remains audible without collapsing mono compatibility
- Orbass and widener do not fight each other

### Phase 5. Tighten AGC role and defaults

Status: mostly complete (current AGC target `-16 dB`; AGC treated as a slow leveler, not a loudness stage).

Next work (optional, only if real-program feedback justifies):

1. Consider adding hidden or advanced controls:
   - deadband/window
   - silence gate threshold
   - low-level recovery speed

Success criteria:

- AGC stabilizes program level
- AGC does not pump noise or dominate loudness

### Phase 6. Improve measurement and verification

Status: partially complete

Completed:

1. Stored verifier baseline artifacts for the default `--verify` path (Phase 6.4).
   - `macOS/Sources/MPXPrime/VerifierBaseline.swift`: Codable `VerifierBaselineRecord` / `VerifierBaselineFile`, per-metric tolerance table, compare/load/save.
   - `macOS/verifier_baselines/default.json`: committed baseline of 8 scenarios × 17 metrics.
   - CLI flags: `--capture-baseline` (writes a fresh baseline), `--baseline-strict` (elevates any drift to exit code 2 / WARN).
   - Default `--verify` auto-compares against the stored baseline; drift is printed as specific `scenario: metric measured X, baseline Y, tolerance ±T` findings and elevates to TIGHT (exit 1).
   - Tolerances tuned to catch the regression class that motivated this (peak ±0.10 dB, LimGR ±0.15 dB, above-60k-ratio ±1.0 dB) while tolerating small FFT / float jitter (~0.01 dB on ratios).
2. Swift Testing migration from XCTest (existing 2 tests) + new per-clipper aliasing test rig (`DSPTestHelpers.swift`, `NonlinearityProbe.swift`, `BassClipperTests.swift`, `DistortionCancelledClipperTests.swift`) documenting pre-refactor baselines at -28.73 dBFS / -56.50 dBFS. Requires `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path macOS` because the CLT toolchain lacks `Testing.framework`; documented in `AGENTS.md`.

Next work:

1. Extend deterministic tests for:
   - mono-bass and widener mono-compatibility behavior
   - RT and RT+ formatting edge cases
2. Add synthetic verification inputs:
   - more real-world dense music classes beyond the current bright/vocal/transient/wide-bass set
   - pink noise and shaped noise classes
   - stereo material with deliberately wide low end
3. Add a lightweight RF/composite analyzer roadmap item:
    - at minimum, show composite spectrum and pilot/RDS occupancy clearly
    - later, optionally add compliance-oriented views similar in spirit to Stereo Tool's FM tooling
4. Extend the stored-baseline mechanism to `--verify-presets` (~20 presets × 3 scenarios) and `--verify-long` (5 focused scenarios). Both currently use hardcoded expectation arrays; same `VerifierBaselineFile` schema applies, just a different file name (`presets.json`, `long.json`). Deferred until the default `--verify` baseline pattern has proven itself in practice.

### Phase 7. Close the commercial DSP gap

Status: open

The topology is already professional-grade. What's missing is the 5% of oversampling, distortion-shaping, and receiver-compatibility detail that commercial vendors spent decades refining. Do these in order — earlier items have the largest audible-impact-per-effort ratio and de-risk later work.

#### 7.1. Oversample the existing nonlinearities — attempted, reverted

An implementation attempt (Lagrange4Interp helper + oversampling wrappers around `BassClipper` at 4× and `DistortionCancelledClipper` at 8×, both with 12th-order Butterworth decimation LP) delivered measurable aliasing improvement on the direct tests but introduced a **chain-level verifier regression** that was not caught by the focused aliasing tests.

With all new stages disabled by default, `--verify` showed `>60k/In` (audio above 60 kHz / in-band ratio) degrading from -49 / -58 dB to -32 / -30 dB on `bright_dense` and `hf_edge_12k`, along with loss of composite peak headroom and new stereo correlation-delta warnings. This is critical because audio content above 60 kHz lands in the pilot/RDS guard band and would degrade RDS reception at the receiver.

Diagnosis stalled after multiple hours: the regression persisted even with the 7.2 pre-emphasis reorder reverted, suggesting the new `Lagrange4Interp` / `BiquadCascade6` state in the generator is subtly affecting other paths via some mechanism that isn't clear from a fast read of the changes. A proper 7.1 needs to be done with tighter incremental verification (verifier-first, not tests-first) so any regression is caught at the point of introduction.

Decision: full revert of 7.1 + 7.2 + 7.3 production source changes. Kept as-is:
- Test infrastructure (`DSPTestHelpers.swift`, `NonlinearityProbe.swift`, per-clipper tests, `ClipperAliasingBaseline.md`) — these are the measurement scaffolding a future 7.1 attempt needs and they document the problem state. The aliasing gates fail on current code with their target thresholds as the documented goal.
- Existing tests migrated from XCTest to Swift Testing (XCTest isn't in the CLT toolchain; `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` works).

Measured aliasing baselines (native-rate clippers, to be cleared by a future 7.1):

| Clipper | Aliasing energy | Target |
|---|---|---|
| `DistortionCancelledClipper` (5111 Hz test) | -28.73 dBFS | -75 dBFS |
| `BassClipper` (113 Hz test) | -56.50 dBFS | -75 dBFS |

Path forward: when re-attempting 7.1, do it incrementally with `--verify` after EACH wrap step, and specifically watch `>60k/In` / `>67k/In` on the hf_edge / bright_dense scenarios. These numbers are RDS-reception-critical and the focused aliasing tests miss them.

**Safety net now in place (Phase 6.4):** The stored-baseline mechanism added in 6.4 would have caught the chain-level regression at the first `--verify` run after any change with output like `Baseline drift: hf_edge_12k: above60kRatioDB measured -30.0 dB, baseline -58.1 dB (-28.1 dB, tolerance ±1.0 dB)`. This removes the primary blocker from re-attempting 7.1 — the silent-drift failure mode that ate hours of diagnosis last time is now loud and specific. Recommended workflow for the retry: enable 7.1 one clipper at a time, run `--verify` after each wrap, and require the baseline drift output to be empty before proceeding to the next stage.

#### 7.2. Pre-emphasis ordering — DONE

Moved pre-emphasis from M/S domain inside `makeCompositeComponents` (`preSum`/`preDiff`) to L/R domain in `processSampleDetailed` (`preL`/`preR`), applied immediately before the pre-encode limiter. The limiter now sees the 10-12 dB HF boost from 50/75 µs pre-emphasis and can peak-control it.

Previously reverted because "broader verification" showed a catastrophic regression: `>60k/In` jumping from -58 dB to -30 dB, composite limiter doing 0 dB GR, peaks dropping below ceiling. That regression was **entirely caused by an INI key collision** (`composite_clipper_enabled` in `Verification.ini` was pre-mapped to `compositeLimiterEnabled` in `AppConfig.swift` line 277) — setting it to `False` to disable the new clipper actually disabled the composite *limiter*. With the key collision fixed (`mpx_clipper_enabled` for the composite clipper), the pre-emphasis reorder produces the clean result originally predicted:

| Metric | Before 7.2 | After 7.2 |
|---|---|---|
| `bright_dense` composite LimGR | 4.11 dB | **2.83 dB** (-1.3 dB less work) |
| `bright_dense` budget margin | -1.59 dB | -1.43 dB (safer) |
| `hf_edge_12k` `>60k/In` | -57.8 dB | -57.8 dB (unchanged — no HF distortion leak) |
| `bright_dense` `>60k/In` | -49.1 dB | -48.8 dB (within tolerance) |

RDS guard band unaffected. Composite limiter fully operational. Peaks reach full deviation.

#### 7.3. Add a real composite clipper stage — attempted, reverted with 7.1

A `CompositeClipper` struct (8× oversampled tanh soft-clip, placed between the composite true-peak limiter and BS.412, wired through `AppConfig` / `RuntimeConfig` / UI with disabled-by-default defaults) was implemented alongside the 7.1 oversampling wrappers. It correctly preserved the subcarrier-bypass invariant and passed all its direct tests.

Reverted together with 7.1 because the shared oversampling infrastructure (`Lagrange4Interp` + `BiquadCascade6` decimation) was implicated in the chain-level verifier regression described under 7.1. A future attempt should land 7.1's oversampling scaffolding first (cleanly, with verifier-first validation), then rebuild `CompositeClipper` on top of that scaffolding.

#### 7.4. Add a 19 kHz pilot notch on the audio path

Commercial processors notch out program content at 19 kHz ±100 Hz so receiver stereo decoders don't confuse program content for pilot. MPX Prime currently relies on the 15 kHz program LP + encoder HF guard, which attenuates but doesn't notch.

1. Add a narrow Q biquad notch at 19 kHz in the encoder-facing audio path (after encoder program LP, before stereo encoding).
2. Expose Q and depth as config; defaults should match Orban guidance (Q ~50, depth >40 dB).

Low-risk, high-receiver-compatibility win.

#### 7.5. Replace the 15 kHz program LP with a linear-phase FIR brick-wall

`programLP` is currently a Butterworth biquad — smooth rolloff, significant content remaining at 19 kHz. Commercial processors use 15 kHz linear-phase FIR brick-walls with ~120 dB stop-band.

1. Design the FIR once at engine-start for the active sample rate; cache coefficients.
2. Measure added latency; if it exceeds the monitor-path budget, keep the FIR only on the transmit path and leave the biquad LP on the monitor path.

Depends on: having stored-baseline verifier artifacts (Phase 6.4) because this will shift the verifier signatures even on disabled-by-default settings, through the spectrum tests.

#### 7.6. Dynamic pre-emphasis ("Smart HF")

Static pre-emphasis boosts HF transients into the clipper regardless of program content. Omnia's "Smart HF" and Orban's HF limiter relax pre-emphasis during HF-heavy transients to reduce clipper workload.

1. Add a lookahead-based HF envelope follower on the L/R signal before pre-emphasis.
2. Dynamically scale the pre-emphasis curve (or add post-emphasis gain reduction) when HF envelope exceeds threshold.
3. Target a few dB of dynamic relaxation on bright transients; verify that de-emphasis at the receiver still recovers the original HF envelope within tolerance.

Optional but high subjective-quality impact.

#### 7.7. Pilot-synchronized limiter control

Amplitude modulation of the composite limiter's control envelope can induce sidebands around the 19 kHz pilot if modulation rates approach pilot subharmonics. Post-limiter injection prevents direct pilot modulation but not upstream sideband generation.

1. Measure: run a strong low-frequency-heavy signal through the chain with the composite limiter driven hard; FFT the output around 19 kHz and check for artifact sidebands.
2. If present: phase-lock the limiter's release control to a pilot subharmonic, or add a narrow notch at 19 kHz in the limiter's sidechain.

Defer until measurement justifies the complexity.

#### 7.8. Deviation estimator and exciter calibration — already implemented

The monitoring card already shows: live deviation peak (kHz), deviation target (configurable via `mpxDeviationKHz`), audio composite peak, budget margin, pilot/RDS injection percentages, and guided calibration steps. The `--verify` output includes deviation kHz per scenario. The core formula `outputPeak × mpxDeviationKHz` is computed in `AudioOutputEngine.swift:1613`.

#### 7.9. Input-side restoration (optional, long-term)

Commercial processors include declipper / dehumfilter / delossifier / dehisser stages for conditioning degraded sources (Omnia "Undo", Stereotool's equivalents). These are genuinely complex algorithms and take significant effort.

Defer unless MPX Prime starts being used for streaming sources where pre-processed audio arrives degraded.

### Swift DSP cleanup checklist

This section is intentionally concrete and implementation-focused.

1. Refactor the final composite path's remaining stateful limiter packaging in micro-steps, rerunning `--verify` after each.
2. Extract the 4× Lagrange-upsample + BiquadCascade6-reconstruction pattern from `CompositeTruePeakLimiter` into a reusable `OversampledNonlinearity<Clipper>` block; wrap `DistortionCancelledClipper` and `BassClipper` with it (see Phase 7.1).
3. Validate and retune:
   - Orbass presets
   - mono-bass defaults
   - widener defaults
   - widener and multiband ordering
4. Add deterministic offline tests for:
   - stereo-to-mono collapse behavior
   - now-playing RT / RT+ formatting edge cases
5. Extend MPX width/compliance checks with longer-run cases beyond the current focused regression gate.
6. Extend the RDS timed-text parser with a documented compatible subset:
   - `Nt:` transmit-count segments
   - escapes for separators
   - optional wrap markers if they are still judged useful
7. Move remaining non-DSP work off the audio callback where practical (RDS string preparation still on render path).

Success criteria:

- loudness and deviation changes are measurable and repeatable
- regressions are detectable without relying only on listening

## Recommended default direction

These are the current practical defaults after the recent gain-structure and final-stage work:

- Wideband AGC target: `-16 dB`
- Wideband AGC attack: `50-80 ms`
- Wideband AGC release: `800-1500 ms`
- Wideband AGC max/min gain: `+12 / -12 dB`
- Final Drive: `6 dB`
- Pre-encode audio limiter: enabled (threshold `0.85`, release `50 ms`)
- Composite limiter: enabled (threshold derived from safety threshold, release `32 ms`)
- Pilot: approximately `8-10%`
- RDS: approximately `3-4%`
- Pilot and RDS: injected post-limiter for constant amplitude
- Final loudness should come primarily from `Final Drive` plus composite protection, not AGC target

## Immediate next step

Phases 7.1 through 7.4 are done. The stored-baseline regression gate (6.4) is active and was essential for landing all four cleanly — it also surfaced the INI key collision that had blocked 7.2 for two sessions.

**Current state**: 19/19 tests green, verifier TIGHT (pre-existing `bright_dense occ999` only), baseline self-matches, RDS guard band clean.

**Recommended next work, in order of diminishing return:**

1. **Phase 7.5 (FIR brick-wall 15 kHz)** — would replace the Butterworth `encoderProgramLP` and the clipper decimation LPs with sharper rolloff. The DC clipper aliasing gate is currently at -38 dBFS (limited by Butterworth near-Nyquist rejection); an 80+ dB stop-band FIR would push it below -75. Also improves stereo subcarrier separation.

2. **Phase 7.8 (deviation estimator + exciter calibration)** — user-facing calibration feature. The math already exists (`peakAbs * mpxDeviationKHz`); what's missing is a UI workflow where the operator enters exciter sensitivity and sees deviation directly in the monitoring card.

3. **Phase 7.6 (dynamic pre-emphasis / "Smart HF")** — new algorithm, significant effort.

4. Non-7.x follow-ups:
   - Do a release smoke pass for live-apply vs restart-required settings on difficult real material.
   - Add gain-structure code comments at each DSP stage.
   - Validate Orbass, mono bass, widener, and multiband interaction on difficult real material.
   - Extend baselines to `--verify-presets` and `--verify-long`.

## Tactical backlog

This section merges the actionable items that used to be split across `bugs.md` and `macOS/TODO.md`.

### Release-blocking / first fixes

1. Add a smoke-test pass for live-apply vs restart-required settings so MPX does not stop unexpectedly during ordinary DSP edits.

### Current sprint tasks

1. Do a release smoke pass for the new live-update path and restart-only settings behavior.
2. Validate Orbass, mono bass, widener, and multiband interaction on difficult real material.
3. Keep refining the calibration workflow only where real operator friction still exists.

### Medium-term maintainability

1. Reduce duplicated filter configuration logic in the biquad/crossover helpers.
2. Replace undocumented DSP magic numbers with named constants and brief references.
3. Simplify and test the RDS group scheduler modes more deterministically.
4. Expand the Swift Testing suite (currently 19 tests covering ring buffer, analysis tap, clipper aliasing gates, clipper fidelity/ceiling) into MPX generation, filters, AGC, and config round-trip coverage. The test target is now functional (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path macOS`).
5. Split the monolithic SwiftUI view model into smaller focused view models over time.
6. Loosen tight coupling between the audio engine and concrete generator types. Add basic dependency-injection seams for system-facing services (now-playing, device discovery) so those paths become testable in isolation.
7. Harden config file watching/reload behavior against race conditions.

## Code-quality priorities

A second view on the backlog, organized by risk/safety priority rather than by subsystem. This captures the same direction of travel as the tactical backlog but makes the priority gradient explicit.

### P0 — Confidence and safety

1. Add deterministic unit tests for the major DSP primitives and stages. Cover filters, limiters, stereo coding, pilot/RDS generation, AGC behavior, and config-driven bypass paths.
2. Add golden-output regression tests for the verification harness. Use fixed inputs and stored tolerances so DSP refactors are safer than eyeballing table deltas.
3. Fix the verification harness bandwidth metric so RDS does not produce misleading occupied-width failures. Isolation runs show the `bright_dense` occupied-bandwidth warning disappears when `en_rds = False`, meaning the current `occupied999Hz` check is counting service subcarriers instead of isolating audio-composite width.
4. Add config round-trip and invalid-input tests for `AppConfig`. Verify clamping, defaults, malformed INI handling, and incompatible setting combinations.
5. Define and test live-apply versus restart-required behavior as code, not just UI guidance. There should be one authoritative decision path for whether a setting can apply live.

### P1 — Structural cleanup

1. Split `MPXGenerator.swift` into stage-focused components — suggested split: oscillators/subcarriers, filters, AGC/dynamics, stereo encoder, RDS encoder, composite limiter/power control, analysis helpers.
2. Split `AudioOutputEngine.swift` by concern — device routing, capture/input transport, render loop glue, metering, monitoring analysis.
3. Split `SwiftUIControlApp.swift` into smaller views and focused state holders. Keep window management separate from feature views; separate feature views from shared controls.
4. Reduce hidden coupling between engine, config, generator, and UI state. Prefer narrow DTO-style runtime config snapshots over broad shared mutable objects.

### P2 — Harden behavior

1. Strengthen validation rules in `AppConfig`. Reject or normalize invalid ranges, invalid text fields, illegal combinations, and impossible sample-rate/block-size choices.
2. Re-tune final-stage composite headroom for decoded-audio stability on vocal/transient material. Isolation runs show the remaining `vocal_sibilant` and `transient_push` RMS-drift warnings are not primarily caused by AGC or multiband, and they improve materially when `sum_level` is reduced from `1.0` to `0.9`.
3. Harden device and routing edge cases. Test missing devices, changed UIDs, rate mismatches, startup with no valid route, and monitor/output transitions.
4. Harden now-playing script integration further. Sanitize external output, bound field lengths, and handle malformed key/value content deterministically. (`NowPlayingScriptRunner.parseSnapshot` already does basic sanitization — extend from there.)
5. Make error reporting more structured. Distinguish user-facing configuration/routing failures from internal runtime failures.

### P3 — Maintainability and performance follow-through

1. Replace more hot-path scalar loops with Accelerate where it materially helps and does not obscure correctness.
2. Add explicit internal documentation for critical DSP invariants. Focus on stage ordering, level assumptions, limiter expectations, and RDS/stereo subcarrier rules.
3. Add small benchmarks or profiling notes for the hottest paths so performance regressions are detectable before they become audible.
4. Create a clearer internal module map. Even while MPX Prime stays a single SwiftPM target, the source tree should reflect subsystem boundaries.

### Done when

- Core DSP stages have deterministic automated tests.
- The verification harness has regression baselines for known signals.
- Runtime config behavior is explicit and testable; live-apply vs restart is enforced in code.
- `MPXGenerator`, `AudioOutputEngine`, and `SwiftUIControlApp` are each materially smaller and more focused.
- Invalid config and routing failures are predictable and bounded.
- Routine refactors can be done with substantially lower regression risk.

## Design constraints

- keep realtime callbacks lock-free and allocation-free
- do not move shell/file/network work into DSP paths
- preserve current integrated RDS and monitoring workflow
- keep monitor-output latency concerns separate from transmit-path quality concerns

## Performance Optimization Opportunities

The following items represent opportunities to improve CPU efficiency while maintaining or enhancing enterprise-grade MPX quality:

1. **Further vDSP utilization** - Replace remaining manual loops in analysis and support code where numerically equivalent and beneficial
2. **RDS string preparation** - Cache RDS byte preparation and avoid repeated string allocations in RDS group generation
3. **Stereo image processing** - Optimize the remaining mid/side energy calculations with vDSP where it stays maintainable
4. **Memory access patterns** - Keep tightening cache-friendly access in input conversion, history capture, and tight DSP support paths
5. **Approximation where appropriate** - Use fast math approximations only where profiling shows real value and verification stays clean

These optimizations should be approached incrementally with verification using the offline verifier to ensure no regression in MPX quality or compliance.

## Real-Time Performance Plan

This section turns the remaining performance work into an explicit execution plan. The priority order is:

1. remove real-time safety hazards first
2. reduce callback CPU in the hottest paths
3. add measurement gates so future tuning stays disciplined

### Phase P1. Make the callback safer under load

Status: mostly complete

Next work:

1. Re-audit all input fallback paths to confirm they stay allocation-free and non-blocking at callback time.

Success criteria:

- no spin waits on the render thread
- no avoidable mutex acquisition on the render thread
- live parameter edits do not introduce audible dropouts under stress

### Phase P2. Cut obvious per-sample waste

Status: partially complete

Next work:

1. Audit the remaining hot scalar DSP support paths for repeated transcendental math:
   - `expf`
   - `powf`
   - repeated coefficient derivation
2. Keep stateful filter and compressor sample processing scalar unless profiling proves a safe vectorized alternative.

Success criteria:

- monitor mode CPU drops measurably in Instruments
- no functional change in offline verification outputs beyond accepted tolerances

### Phase P3. Consolidate analysis and metering work

Status: partially complete

Next work:

1. Reduce any remaining duplicate passes over the same render buffer where that can be done without making the code opaque.
2. Extend Accelerate use where the math is clearly equivalent and the code stays maintainable:
   - any remaining scope downsampling helpers that still justify it after profiling
3. Re-profile the callback after the current analysis cleanup so the next work is guided by real hotspots rather than by source inspection alone.

Success criteria:

- fewer full-buffer passes per callback
- metering and scope features scale down when not visible
- callback CPU remains predictable with the monitoring window closed

### Phase P4. Tighten memory and data movement

Status: partially complete

Next work:

1. Audit the remaining output-spectrum and scope-readback helpers for any residual unnecessary copying or oversized scratch buffers.
2. Re-check fallback and uncommon capture paths for any remaining per-callback allocation or avoidable data churn.
3. Keep all hot-path buffers long-lived and preallocated for worst-case block sizes already supported by the engine.

Success criteria:

- no remaining known per-callback heap allocation in audio or capture paths
- lower memory bandwidth pressure in adaptive input mode

### Phase P5. Make performance regressions visible

Status: open

Next work:

1. Add a profiling checklist for every release candidate:
   - tone mode
   - live input mode
   - monitor mode
   - worst-case processing enabled
2. Record baseline CPU measurements for representative configurations and keep them in project docs.
3. Extend verification so performance-sensitive refactors are always checked against:
   - MPX peak behavior
   - safety limiter gain reduction
   - pilot and RDS stability
   - mono/stereo image behavior
4. Add at least one long-run stress scenario aimed at catching callback overruns or transport instability.

Success criteria:

- CPU regressions are caught before release
- DSP refactors are backed by both performance data and signal-quality verification

### Recommended execution order

1. Capture baseline Instruments data and keep it current.

## References

### Enterprise / hardware

- Telos Omnia.9: MPX output and composite-domain clipping guidance
  - https://docs.telosalliance.com/docs/setting-up-omnia9-for-fm-pre-emph-output-via-aesebu
- Telos Omnia Direct: MPX-over-AES at high rates
  - https://docs.telosalliance.com/docs/using-mpx-over-aes-omnia-direct-on-the-omnia9
- Telos RDS integration guidance
  - https://docs.telosalliance.com/docs/rds
- Telos RDS bit-error guidance
  - https://docs.telosalliance.com/docs/ensuring-rds-bit-errors-do-not-occur
- Orban 5518 specs
  - https://www.orban.com/specifications-optimodfm5518
- Orban 8700i specs
  - https://www.orban.com/specifications-optimod8700i
- Orban 8700i key features
  - https://www.orban.com/keyfeatures-optimod8700i

### Software

- Stereo Tool FM transmitter documentation
  - https://www.thimeo.com/documentation/fm-transmitter.html
- Stereo Tool FM transmitter help
  - https://help.stereotool.com/7.83/fm_transmitter.shtml
- Stereo Tool limiting/clipping overview
  - https://help.stereotool.com/7.40/limiting_and_clipping.shtml
- Thimeo MicroMPX
  - https://www.thimeo.com/micrompx/
- BreakawayOne product overview
  - https://www.breakawaysoftware.com/breakawayone
- BreakawayOne FM processor product page
  - https://www.breakawaysoftware.com/store/p/breakawayone-fm-processor
