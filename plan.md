# MPX Prime FM/MPX Roadmap

## Goal

Bring MPX Prime closer to a broadcast-grade FM composite generator and processor by:

- fixing current gain-structure bugs
- separating operating-level control from output calibration
- moving final loudness control into the composite/MPX domain
- preserving pilot and RDS integrity under loudness processing
- improving calibration, metering, and verification

This plan is based on current MPX Prime behavior plus publicly available official material from Telos/Omnia, Orban, Stereo Tool, and Breakaway.

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

- the final composite limiter path is improved, but it is still an evolved approximation rather than a deliberately designed composite clipper with one clear architecture
- widener, mono bass, Orbass, and multiband interaction still needs broader preset-level validation on real program material beyond the current focused sweep
- pilot/RDS/headroom telemetry exists, but there is still no explicit deviation estimator or exciter-calibration workflow
- some real-time and monitoring paths still need performance cleanup:
  - per-callback capture-buffer allocation in some fallback paths
  - spectrum snapshot/buffer reuse beyond the current cached FFT path
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

## Target architecture

### Proposed FM chain

1. Input trim / source conditioning
2. Wideband AGC gain rider
3. Tone shaping and enhancement
4. Bass management / stereo image conditioning
5. Multiband / other audio-domain dynamics
6. Pre-emphasis
7. Stereo coder
8. Pilot and RDS injection
9. Oversampled composite limiter / composite clipper
10. MPX output calibration trim
11. Hardware output

### Control separation

MPX Prime should clearly distinguish:

- `Input Gain`: source trim
- `Wideband AGC Target`: average operating platform
- `Final Drive`: how hard we hit final loudness protection
- `MPX Output Level` or `Output Calibration`: output alignment to exciter / sound card / deviation target

Users should not need to abuse AGC target to get acceptable loudness.

## Implementation plan

### Phase 1. Fix the gain structure

Status: partially complete

Still open:

1. Add one internal gain-structure note per stage in code comments so future tuning stays coherent.

Success criteria:

- output trim measurably changes MPX output level
- AGC target no longer has to be set unrealistically hot to get normal modulation
- ordinary DSP controls can be changed live without forcing engine restarts

### Phase 2. Add a proper final composite stage

Status: partially complete

Next work:

1. Do not attempt another large helper extraction of the final composite stage until there is a tighter micro-refactor plan.
2. Extract only pure calculations first:
   - pre-limiter ceiling math
   - post-limiter ceiling math
   - composite budget / margin math
3. Keep stateful pieces in place until the pure calculations are isolated and verified:
   - reservation envelope
   - composite limiter state
   - smoother state
   - safety limiter state
4. After each micro-step, rerun the offline verifier and compare:
   - worst MPX peak
   - worst safety limiter GR
   - worst composite margin
   - scenario table deltas
5. Revisit whether the main loudness limiter should remain fully audio-composite only, with the full-MPX limiter reserved strictly for safety.
6. Preserve pilot lock and RDS readability while increasing usable composite loudness.
7. Strengthen long-run width/compliance regression checks beyond the current focused mode.
8. Move from in-code signature checks toward stored baseline artifacts if they prove useful.

Success criteria:

- higher subjective loudness without excessive HF splatter
- pilot and RDS remain stable
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

Status: partially complete

1. Keep wideband AGC as a slow leveler, not a loudness stage.
2. Re-evaluate defaults after Phase 1 and Phase 2 are in place.
   Current implemented default:
   - `-16 dB`
3. Consider adding hidden or advanced controls later if needed:
   - deadband/window
   - silence gate threshold
   - low-level recovery speed

Success criteria:

- AGC stabilizes program level
- AGC does not pump noise or dominate loudness

### Phase 6. Improve measurement and verification

Status: partially complete

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
4. Grow `--verify-long` from a focused manual tool into a stricter regression gate with saved expected envelopes or stored baseline artifacts.

### Swift DSP cleanup checklist

This section is intentionally concrete and implementation-focused.

1. Treat the current final composite path as the verified baseline until a tighter refactor plan is complete.
2. Refactor the final composite path only in micro-steps:
   - pure ceiling math first
   - budget-margin math second
   - stateful limiter packaging last
   - rerun `--verify` after every micro-step
3. Validate and retune:
   - Orbass presets
   - mono-bass defaults
   - widener defaults
   - widener and multiband ordering
4. Add deterministic offline tests for:
   - stereo-to-mono collapse behavior
   - now-playing RT / RT+ formatting edge cases
5. Keep the MPX width/compliance checks as a regression gate and extend them with longer-run cases.
6. Extend the RDS timed-text parser with a documented compatible subset:
   - `Ns:` duration segments
   - `Nt:` transmit-count segments
   - escapes for separators
   - optional wrap markers if they are still judged useful
7. Move remaining non-DSP work off the audio callback where practical.
8. Keep shrinking the final composite cleanup into verifier-backed micro-steps until the stateful stage can be isolated safely.

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
- Composite limiter: enabled
- Pilot: approximately `8-10%`
- RDS: approximately `3-4%`
- Final loudness should come primarily from `Final Drive` plus composite protection, not AGC target

## Immediate next step

The next quality improvement should be:

1. remove the remaining per-callback heap allocations from the capture/input conversion paths
2. do a release smoke pass for live-apply versus restart-required settings on difficult real material
3. add stronger config/input validation in `AppConfig`

This keeps the plan focused on the actual remaining work instead of repeating steps that are already done.

## Tactical backlog

This section merges the actionable items that used to be split across `bugs.md` and `macOS/TODO.md`.

### Release-blocking / first fixes

1. Remove per-callback heap allocations from the capture/input conversion paths.
2. Add stronger config/input validation in `AppConfig`.
3. Add a smoke-test pass for live-apply vs restart-required settings so MPX does not stop unexpectedly during ordinary DSP edits.

### Current sprint tasks

1. Remove per-callback heap allocations from the capture/input conversion paths.
2. Do a release smoke pass for the new live-update path and restart-only settings behavior.
3. Validate Orbass, mono bass, widener, and multiband interaction on difficult real material.
4. Keep refining the calibration workflow only where real operator friction still exists.

### Medium-term maintainability

1. Reduce duplicated filter configuration logic in the biquad/crossover helpers.
2. Replace undocumented DSP magic numbers with named constants and brief references.
3. Simplify and test the RDS group scheduler modes more deterministically.
4. Expand the XCTest suite beyond ring-buffer behavior into MPX generation, filters, and config round-trip coverage.
5. Split the monolithic SwiftUI view model into smaller focused view models over time.
6. Loosen tight coupling between the audio engine and concrete generator types.
7. Add basic dependency-injection seams for system-facing services such as now-playing and device discovery.
8. Sanitize external now-playing script output before using it in RT/RT+ paths.
9. Harden config file watching/reload behavior against race conditions.

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
5. **Buffer reuse** - Eliminate any remaining per-call scratch churn in capture and analysis paths
6. **Approximation where appropriate** - Use fast math approximations only where profiling shows real value and verification stays clean

These optimizations should be approached incrementally with verification using the offline verifier to ensure no regression in MPX quality or compliance.

Current remaining performance focus:

- further vDSP utilization in DSP processing loops
- additional RDS string preparation caching
- remaining stereo-image and scope-helper optimization
- ensuring cache-friendly access patterns in tight DSP loops

## Real-Time Performance Plan

This section turns the remaining performance work into an explicit execution plan. The priority order is:

1. remove real-time safety hazards first
2. reduce callback CPU in the hottest paths
3. add measurement gates so future tuning stays disciplined

### Phase P1. Make the callback safer under load

Status: partially complete

Completed:

1. Removed render-thread busy waiting from `StereoInputRingBuffer`.
2. Removed unconditional runtime-config lock acquisition from the audio callback by adding an atomic pending fast path.

Next work:

1. Ensure runtime apply never performs heavy filter or compressor reconfiguration directly inside the callback unless it is proven glitch-free and bounded.
2. Re-audit all input fallback paths to confirm they stay allocation-free and non-blocking at callback time.

Success criteria:

- no spin waits on the render thread
- no avoidable mutex acquisition on the render thread
- live parameter edits do not introduce audible dropouts under stress

### Phase P2. Cut obvious per-sample waste

Status: partially complete

Completed:

1. Precomputed monitor-demod coefficients that depend only on sample rate or fixed timing constants.
2. Precomputed Orbass smoothing and adaptation coefficients that did not need per-sample recalculation.

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

Completed:

1. Made scope/history capture and loudness measurement visibility-aware.
2. Removed non-throttled stereo-meter passes that only fed throttled UI updates.
3. Centralized throttled render analysis in one helper and split stereo levels from stereo image metrics so hidden-monitor states do less work.
4. Extended Accelerate use in hot analysis helpers:
   - vectorized input format conversion where practical
   - chunked/vectorized scope and history write helpers
   - cheaper stereo image metrics derived from existing level totals plus dot products

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

Completed:

1. Removed adaptive-read scratch copying in the input ring buffer by interpolating directly from stable published ring data.
2. Made mono capture conversion more cache-friendly:
   - mono `Int16` / `Int32` input now converts into a single mono scratch buffer
   - mono `Float32` input no longer expands into temporary stereo buffers before ring writes
3. Reduced history-buffer write amplification:
   - stereo and mono scope history writes now use chunked/vectorized helpers
   - pre-MPX raw stereo history writes now use chunk copies plus in-place clipping
4. Reduced history-buffer readback cost:
   - raw window extraction now uses contiguous chunk copies instead of per-sample wrapped reads
   - scope-window extraction now scans contiguous chunks instead of doing modulo work per sample
5. Gave the pre-MPX spectrum path its own shorter history depth instead of reusing the full scope-history retention.

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

1. Remove ring-buffer busy waiting and callback locks.
2. Precompute monitor-demod and Orbass coefficients.
3. Gate scope and loudness work by visibility and usage.
4. Revisit adaptive-read scratch copying only after the safety work above is complete.
5. Capture baseline Instruments data and keep it current.

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
