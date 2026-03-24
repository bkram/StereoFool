# StereoFool FM/MPX Roadmap

## Goal

Bring StereoFool closer to a broadcast-grade FM composite generator and processor by:

- fixing current gain-structure bugs
- separating operating-level control from output calibration
- moving final loudness control into the composite/MPX domain
- preserving pilot and RDS integrity under loudness processing
- improving calibration, metering, and verification

This plan is based on current StereoFool behavior plus publicly available official material from Telos/Omnia, Orban, Stereo Tool, and Breakaway.

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

Takeaway for StereoFool:

- if we want competitive FM loudness and cleanliness, final loudness control must move into an oversampled composite stage
- RF/compliance visibility should eventually be first-class, not an afterthought

### Breakaway observations

BreakawayOne's official public material is less detailed about internal FM/MPX mechanics, but it does confirm:

- FM-specific cores exist as a distinct product mode
- BS.412 support matters enough to be a product-level feature
- "back-end peak control" is a key design element
- RDS is modular and considered part of the FM ecosystem
- a separate low-latency monitor path is useful operationally

Takeaway for StereoFool:

- treat FM as a dedicated processing/output topology
- keep low-latency monitoring as a separate design concern from the highest-quality transmit path
- make peak control at the back end a central component, not a side effect

### Limits of public research

Breakaway does not appear to publish the same level of public technical detail about its composite clipping path that Stereo Tool, Omnia, and Orban do. We should not infer exact internal algorithms from marketing copy alone.

## Current StereoFool status

### Completed recently

- `outputGain` is now active in the final render path and exposed in the UI as `MPX Output Level`
- a dedicated `Final Drive` stage now exists ahead of the final composite protection path
- `limit_mpx` is now active in the render path instead of being configured-but-unused
- the old simple composite clamp has been replaced with a more useful final limiter stage with fast attack, hold, controlled release, and soft-knee clipping
- AGC telemetry was added to Monitoring and DSP Overview
- final-stage telemetry was added to Monitoring and DSP Overview:
  - live limiter gain reduction
  - held max gain reduction
  - full-MPX safety limiter gain reduction
  - final MPX peak
- pilot/RDS/audio budget telemetry and explicit composite-budget health state were added
- the widener path was rebuilt into a restrained band-limited widener with stereo-image protection
- a dedicated `Mono Bass` stage was added ahead of the widener/multiband image path
- Orbass presets and UI now match the live adaptive Orbass DSP path
- broadcast-chain presets were added in the `Processing` -> `Limiter` tab:
  - `Balanced Music`
  - `CHR / Dance`
  - `Punchy Music`
  - `Speech / Talk`
- defaults were retuned around the current chain:
  - wideband AGC target `-16 dB`
  - composite limiter enabled by default
  - final drive `6 dB`

### Remaining quality gaps

### 1. Pilot/RDS calibration visibility is improved, but still text-heavy

Monitoring now exposes pilot, RDS, audio-composite peak, budget margin, and a composite-budget state indicator, but calibration is still mostly presented as status text rather than a dedicated calibration workflow.

Impact:

- users can make the chain loud, but they still cannot see pilot and RDS contribution clearly
- exciter alignment remains more trial-and-error than it should be

### 2. AGC is improved, but still needs validation against the stronger final stage

Wideband AGC is now behaving more like a platform leveler, but its defaults and range should be validated further once the oversampled composite stage exists.

### 3. Stereo enhancement is better, but still needs dedicated validation

StereoFool now has a more professional stereo-image path than before, but it still needs deliberate listening and measurement work.

Impact:

- mono bass, widener, Orbass, and multiband interactions still need preset-level validation
- stereo/correlation metering now exists, but there is still no stronger compliance-style validation workflow or history
- width behavior is still tuned by ear rather than by a formal stereo-verification workflow

### 4. Deterministic verification exists, but coverage is improving

The chain is now audibly and operationally better, and the offline verifier exists, but scenario coverage and golden-baseline checks are still limited.

Completed recently:

- added brighter and more program-like stress scenarios:
  - `bright_dense`
  - `vocal_sibilant`
  - `transient_push`
  - `wide_bass`
- added decoded-audio quality checks:
  - correlation drift
  - side-to-mid retention
  - RMS drift
- added a focused preset sweep for:
  - `5B AC/Pop`
  - `5B CHR/EDM`
  - `5B Rock`
  - `5B Talk`
  - `5B News`
  - `5B Urban`
  - `5B Dance`
- current post-build preset sweep status is:
  - `5B AC/Pop`: `OK`
  - `5B CHR/EDM`: `OK`
  - `5B Rock`: `OK`
  - `5B Talk`: `OK`
  - `5B News`: `OK`
  - `5B Urban`: `OK`
  - `5B Dance`: `OK`
- added explicit MPX width/compliance checks:
  - `Occ999 Hz`
  - `>60k/In`
  - `>67k/In`
- added scenario-level width/compliance expectations, including a previously failing `bright_dense` case that now verifies `OK`
- added a focused long-run compliance/regression mode:
  - `--verify-long`
  - current 5-second baseline verifies `OK`

### 5. Swift DSP implementation still has cleanup debt

StereoFool's Swift DSP is now credible and effective, but there are still implementation-level loose ends that should be addressed before treating the chain as fully mature.

Loose ends:

- the final composite limiter path is improved, but it is still an evolved approximation rather than a deliberately designed composite clipper with one clear architecture
- `Halfband2xFIR` still exists alongside the newer internal limiter oversampling path, so the codebase still has two overlapping oversampling ideas instead of one coherent approach
- widener, mono bass, Orbass, and multiband interaction still needs broader preset-level validation on real program material beyond the current focused sweep
- pilot/RDS/headroom telemetry exists, but there is still no explicit deviation estimator or exciter-calibration workflow
- some real-time and monitoring paths still need performance cleanup:
  - input ring buffer locking
  - per-callback capture-buffer allocation in some fallback paths
  - FFT/spectrum scratch reuse
  - RDS wall-clock and string preparation work that should move off the render path

Practical implication:

- the Swift DSP core is strong enough to continue building on directly
- the next quality gains come from cleanup, validation, and measurement discipline rather than from rewriting out of Swift
- the final composite stage is sensitive enough that even a structural refactor can change output measurably, so all cleanup there must be verification-backed and incremental

### 7. RDS text syntax is functional, but still behind established tooling

StereoFool already supports timed PS/RT sequences such as `10s:Text/10s:Other Text`, but it does not yet match the more mature public user-facing syntax that processors such as Stereo Tool expose.

What StereoFool already supports:

- timed text segments with `Ns:Text`
- slash-separated PS and RT sequences
- now-playing macro expansion for RT

Useful compatibility work that can be implemented clean-room from public documentation:

- transmit-count syntax such as `Nt:Text`
- escape handling for literal separators and control characters
- optional word-wrap control markers
- a clearer documented grammar for timed/dynamic PS and RT text

Constraints:

- this should be implemented from public documentation only
- do not rely on reverse engineering or copied parser behavior
- preserve StereoFool-specific macro support (`{artist}`, `{title}`, `{date}`, `{time}`, etc.)

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

StereoFool should clearly distinguish:

- `Input Gain`: source trim
- `Wideband AGC Target`: average operating platform
- `Final Drive`: how hard we hit final loudness protection
- `MPX Output Level` or `Output Calibration`: output alignment to exciter / sound card / deviation target

Users should not need to abuse AGC target to get acceptable loudness.

## Implementation plan

### Phase 1. Fix the gain structure

Status: largely complete

Completed:

1. Wired `outputGain` into the actual signal path.
2. Renamed/exposed it in UI/docs as `MPX Output Level`.
3. Added a distinct `Final Drive` so users do not need to misuse AGC target or output calibration for loudness.
4. Activated the final MPX safety limiter in the real render path.

Still open:

1. Decide whether monitor audio should use a separate monitor gain instead of reusing transmit output trim.
2. Add one internal gain-structure note per stage in code comments so future tuning stays coherent.

Success criteria:

- output trim measurably changes MPX output level
- AGC target no longer has to be set unrealistically hot to get normal modulation

### Phase 2. Add a proper final composite stage

Status: partially complete

Completed:

1. Added a real `Final Drive` parameter ahead of final protection.
2. Improved the composite limiter from a simple clamp to a more useful final-stage limiter/clipper.
3. Added live and held limiter metering so the final stage can be tuned empirically.
4. Moved `Final Drive` to the audio-composite path so pilot and RDS remain calibrated separately.
5. Added a filtered internal oversampling/decimation path inside the final limiter.
6. Added subcarrier-aware audio reservation ahead of the full MPX sum.
7. Added an offline verification baseline for the current final-stage behavior:
   - current config verifies `OK`
   - worst MPX peak `-0.14 dBFS`
   - worst safety limiter GR `0.0 dB`
   - worst composite margin `0.0 dB`
8. Added explicit encoder-side bandwidth control:
   - steeper program low-pass
   - final encoder-facing bandwidth guard
   - dynamic HF compliance guard ahead of stereo encode/pre-emphasis
9. Added verifier-backed MPX width/compliance checks and brought the `bright_dense` case back to `OK`
10. Added a longer focused compliance/regression verifier mode for program-material cases (`--verify-long`)

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
7. Either fix or retire the current `Halfband2xFIR` helper so the codebase has one coherent oversampling approach instead of two partial ones.
8. Add long-run width/compliance regression checks, not just 2-second deterministic cases.
9. Add baseline comparison storage or signature snapshots for the long-run verifier.

Success criteria:

- higher subjective loudness without excessive HF splatter
- pilot and RDS remain stable
- output still respects configured deviation targets
- bright/dense material stays inside the explicit verifier width/compliance envelope
- structural cleanup of the final stage does not change verifier output unless intentionally retuned

### Phase 3. Calibrate pilot, RDS, and MPX headroom

Status: in progress

Completed:

1. Added pilot, RDS, audio-composite, and budget-margin telemetry to Monitoring / DSP Overview.
2. Added an explicit composite-budget health indicator (`Safe`, `Tight`, `Risk`).
3. Added full-MPX safety limiter telemetry.
4. Added a fixed `0-100 kHz` modulation display with target-aware warning behavior.

Next work:

1. Revisit defaults for:
   - pilot injection
   - RDS injection
   - composite headroom
2. Add clearer calibration indicators and warning states for:
   - pilot %
   - RDS %
   - audio-composite peak
   - composite budget margin
   - estimated deviation peak
   - full-MPX safety limiter engagement
3. Document expected exciter integration:
   - when StereoFool pre-emphasis is on, external pre-emphasis must be off
4. Add a dedicated calibration panel or workflow instead of relying mainly on status cards.

Success criteria:

- defaults are sane without requiring guesswork
- users can see whether the chain is calibrated rather than just "loud"

### Phase 4. Validate stereo image, mono bass, and Orbass interaction

Status: in progress

Completed:

1. Added a dedicated `Mono Bass` stage and widener controls that are less primitive than the old full-band M/S gain block.
2. Reworked the widener so it is band-limited, normalized, and guarded against runaway side energy.
3. Activated the adaptive Orbass path so Orbass UI/presets and live DSP finally describe the same thing.

Next work:

1. Add image presets such as `Safe FM`, `Open Music`, and `Wide CHR`.
2. Validate mono compatibility and low-end stability on difficult program material.
3. Add a stronger stereo-verification workflow or history view instead of relying only on instantaneous meters.

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

Completed:

1. Added live AGC telemetry.
2. Added live and held final-limiter telemetry.
3. Added an offline verification harness with deterministic scenarios and exit codes.
4. Added command-line verification mode:
   - `swift run --package-path macOS StereoFool --verify --seconds 5`
5. Added verifier output for:
   - MPX peak
   - estimated deviation
   - composite limiter GR
   - safety limiter GR
   - audio-composite peak
   - pilot and RDS injection
   - composite budget margin
   - AGC reduction
6. Added verifier output for MPX width/compliance:
   - occupied bandwidth proxy (`Occ999 Hz`)
   - energy above 60 kHz relative to in-band
   - energy above 67 kHz relative to in-band

Next work:

1. Extend deterministic tests for:
   - `outputGain` behavior
   - composite limiter / clipper peak behavior
   - pilot and RDS injection integrity
   - mono-bass and widener mono-compatibility behavior
2. Add synthetic verification inputs:
   - mono 1 kHz tone
   - pink noise
   - more real-world dense music classes beyond the current bright/vocal/transient/wide-bass set
   - stereo material with deliberately wide low end
3. Add a lightweight RF/composite analyzer roadmap item:
   - at minimum, show composite spectrum and pilot/RDS occupancy clearly
   - later, optionally add compliance-oriented views similar in spirit to Stereo Tool's FM tooling
4. Add stored baseline comparisons so refactors can be checked against a known-good verifier signature instead of relying only on pass/fail.
5. Grow `--verify-long` from a focused manual tool into a stricter regression gate with saved expected envelopes.

### Swift DSP cleanup checklist

This section is intentionally concrete and implementation-focused.

1. Treat the current final composite path as the verified baseline until a tighter refactor plan is complete.
2. Refactor the final composite path only in micro-steps:
   - pure ceiling math first
   - budget-margin math second
   - stateful limiter packaging last
   - rerun `--verify` after every micro-step
3. Choose one oversampling strategy for the final limiter and remove the redundant one.
4. Validate and retune:
   - Orbass presets
   - mono-bass defaults
   - widener defaults
   - widener and multiband ordering
5. Add deterministic offline tests for:
   - MPX peak control
   - pilot/RDS integrity
   - stereo-to-mono collapse behavior
   - now-playing RT / RT+ formatting edge cases
6. Keep the MPX width/compliance checks as a regression gate and extend them with longer-run cases.
7. Extend the RDS timed-text parser with a documented compatible subset:
   - `Ns:` duration segments
   - `Nt:` transmit-count segments
   - escapes for separators
   - optional wrap markers if they are still judged useful
8. Move remaining non-DSP work off the audio callback where practical.
9. Keep shrinking the final composite cleanup into verifier-backed micro-steps until the stateful stage can be isolated safely.

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

1. add baseline comparison/signature checks to `--verify-long`
2. continue only small state-safe DSP cleanups around the final stage
3. then retune image-stage presets and interactions from measurements instead of intuition

Completed already:

- the final composite path is frozen as the verified baseline
- pure final-stage math extraction is underway
- `--verify` is now the gating check after each micro-step

This keeps the plan focused on the actual remaining work instead of repeating steps that are already done.

## Design constraints

- keep realtime callbacks lock-free and allocation-free
- do not move shell/file/network work into DSP paths
- preserve current integrated RDS and monitoring workflow
- keep monitor-output latency concerns separate from transmit-path quality concerns

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
