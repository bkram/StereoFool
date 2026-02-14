# StereoFool TODO

## In Progress

## Pending

### Audio Pipeline

- [ ] Lock-free SPSC ring buffer for scope/meter data
- [ ] Move scope updates to background thread
- [ ] Input underrun crossfade

### RDS

- [ ] Sample-counter RDS timing (replace Date())
- [ ] Pre-compute RDS biphase shaping
- [ ] RDS level scaling - may be too hot (0.25 amplitude at rdsLevel=75)
- [ ] Monitor stereo demod with PLL (currently depends on generator's lastSubcarrierSample)
- [ ] Sample-rate change phase alignment

### DSP

- [ ] Batch biquad processing for multiband crossover
- [ ] Orbass HF noise investigation

### UI

- [ ] Reset to defaults button

---

## Completed

- ✅ Pre-allocate all scratch/conversion buffers
- ✅ vDSP metering
- ✅ Meter/scope throttling (512-frame interval)
- ✅ vDSP buffer clearing
- ✅ App Sandbox entitlements
- ✅ Dark mode semantic colors
- ✅ Accessibility labels
- ✅ Window close behavior
- ✅ Separate scope windows
- ✅ RDS phase-lock to pilot
- ✅ Composite limiter
- ✅ Preemphasis/deemphasis bilinear filters
- ✅ SineCosOsc with drift correction

## Plan for Codex: make pre-emphasis behave like broadcast processing

### Goal

Stop HF pre-emphasis boost from driving the **composite limiter** (and causing pumping / dullness / stereo collapse). Broadcast processors do most hard limiting/clipping **in the pre-emphasized domain** and keep the composite limiter as **safety-only**. ([help.stereotool.com][1])

---

## 0) Add new processing stage in MPXGenerator

Create a new stage between:

* `base = preSum.process(base)` / `diff = preDiff.process(diff)`
* and MPX construction

This stage will do **pre-emphasis-aware control** on **Mid/Side** (M/S).

Broadcast rationale: pre-emphasis increases HF energy, so processors add HF limiting/clipper control to avoid overdeviation and pumping. ([Orban][2])

---

## 1) Refactor `processSample` to Mid/Side earlier

**Codex tasks:**

1. Replace the current “base/diff” computation with explicit Mid/Side:

   * `M = 0.5*(l+r)`
   * `S = monoMode ? 0 : 0.5*(r-l)`
2. Apply **pre-emphasis to M and S** (your corrected `PreemphasisFilter`).

**Implementation steps:**

* In `processSample`, right after `protectStereoImage(...)` (or where you currently compute `base/diff`), do:

```swift
var M = 0.5 * (l + r)
var S = monoMode ? 0.0 : (0.5 * (r - l))

M = preSum.process(M)
S = preDiff.process(S)
```

---

## 2) Add “pre-emphasis domain limiting” on M and S

### 2A) Minimal version (fast, works)

**Codex tasks:**

1. Add two limiters:

   * `var midLimiter = LookaheadLimiter()`
   * `var sideLimiter = LookaheadLimiter()`
2. Configure them in `init(...)` and `setSampleRate(...)`.
3. Process M/S after pre-emphasis:

   * Use slightly tighter threshold on side to reduce stereo pumping.

**Suggested defaults (starting point):**

* `lookaheadMS`: 1.0
* `thresholdMid`: 0.985
* `thresholdSide`: 0.965
* fast attack (your LookaheadLimiter already has fixed attack/release; keep as-is initially)

**Where in code:**
Immediately after pre-emphasis:

```swift
M = midLimiter.process(M)
S = sideLimiter.process(S)
```

---

## 3) Move `sumLevel/diffLevel` to after that limiter

Right now `sumLevel/diffLevel` are applied before pre-emphasis in your current code. For predictable limiting, apply them after pre-emphasis control (so the limiter is controlling the true pre-emphasized content, not an already scaled version that may change with settings).

**Codex tasks:**

* After M/S limiting:

```swift
M *= sumLevel
S *= diffLevel
```

---

## 4) Rebuild MPX from M/S

**Codex tasks:**

* Replace:

```swift
var base = ...
var diff = ...
var mpx = (base + (diff * sub) + pilot + rds) * deviationScale
```

* With:

```swift
let base = M
let diff = S
var mpx = (base + (diff * sub) + pilot + rds) * deviationScale
```

(This is functionally the same, but now “base/diff” are controlled pre-emphasis-aware.)

---

## 5) Downgrade compositeLimiter to “safety only”

Broadcast-style: composite limiter should only catch rare overs; most control happens earlier. ([help.stereotool.com][1])

**Codex tasks:**

1. Increase composite limiter threshold:

   * change default from `0.98` to something like `0.995`–`0.999`
2. Optionally slow the release:

   * keep your `releaseMS` but consider 120–200ms.

**Implementation:**

* In `CompositeTruePeakLimiter.configure` keep clamp, but use higher defaults in config.
* In config UI, label it “Composite safety limiter”.

---

## 6) Add instrumentation to verify the fix

**Codex tasks:**

1. Add peak meters (non-locking if in RT thread) for:

   * `abs(M_pre)` before limiter
   * `abs(M)` after limiter
   * same for `S`
   * `abs(mpx)` before compositeLimiter
   * composite limiter gain reduction (`gain`)
2. Log “composite limiter engaged percentage” over time.

Expected outcome:

* composite limiter triggers rarely
* pre-emphasis no longer causes whole-program pumping

---

## 7) Optional upgrade: HF-only guard (more “broadcast”)

Instead of limiting the full M/S, split off HF and only limit HF so bass never ducks.

**Codex tasks:**

1. Add 1st/2nd order HPF at ~2.5–3 kHz for M_pre and S_pre.
2. Compute:

   * `HF = HP(x)`
   * `LF = x - HF`
3. Limit/clip HF only
4. Recombine: `x = LF + HF_limited`

This mirrors “high-frequency limiters to control overload due to pre-emphasis”. ([Orban][2])

---

## Acceptance checks

Codex should run these tests:

1. White noise / cymbal-heavy content:

   * No audible pumping
   * No sudden stereo collapse
2. Disable composite limiter entirely:

   * M/S pre-limiting alone should keep MPX mostly within range
3. Enable composite limiter:

   * Engagement should be rare

---

## Deliverables Codex should produce

1. A commit that:

   * Adds mid/side limiters
   * Moves sum/diff scaling
   * Raises composite limiter threshold
2. A short debug panel output showing:

   * mid/side limiter activity
   * composite limiter activity

[1]: https://help.stereotool.com/7.83/fm_transmitter.shtml?utm_source=chatgpt.com "Stereo Tool 7.83 Help: FM Transmitter"
[2]: https://www.orban.com/s/Broadcast-Transmission-Audio-Processing.pdf?utm_source=chatgpt.com "transmission audio processing - Orban"

## Objective

Refactor and harden the **AudioOutputEngine + MPXGenerator + RDS coder** into a production-grade, glitch-free real-time pipeline suitable for Codex execution: **no locks / no allocations / no file or network IO on the audio render thread**, deterministic CPU, and testable DSP blocks.

---

## Deliverables

1. **RT-safe audio render path**

   * No `NSLock`, no `DispatchSemaphore`, no `URLSession`, no Swift `Array` growth, no string processing, no regex, no heap allocation.
2. **Two-thread model**

   * **Audio thread**: render MPX/monitor audio, push lightweight telemetry.
   * **Control/worker thread(s)**: build RDS bitstreams, parse/prepare text, manage schedules, load files/URLs, update DSP configs.
3. **Telemetry subsystem**

   * Lock-free meter + scope snapshots, stable peak decay, bounded memory.
4. **Correctness & performance tests**

   * Unit tests for DSP primitives, RDS CRC/groups, and regression tests for clipping/levels.
5. **Profiling + acceptance gates**

   * CPU budget checks and underrun-resistance checks.

---

## Phase 0 — Baseline and constraints

### Codex tasks

* Add a `RealtimeRules.md` in repo:

  * Audio callback rules: no locks, no allocations, no syscalls, no I/O.
* Add lightweight logging counters (atomic) for:

  * render callback count, max render duration (mach absolute time), ring underflows/overflows.
* Add a “stress mode” config:

  * smallest buffer size, 192 kHz render, multiband+orbass+rds enabled.

### Acceptance

* Can run for 10 minutes with stress mode without dropouts on target machine (or simulated workload if no hardware).

---

## Phase 1 — Remove locks and dynamic memory from the audio callback

### Current issues in your code

* `meterLock` is taken in UI getters and in `stop()`, but meter updates and scope writes occur in capture callback and render callback without a strict RT contract.
* RDS text resolution can call `URLSession` + regex + file IO (in `resolveTextMarkers`), which must never be reachable from RT.
* Scope history uses `[Float]` and writes per sample; ok if preallocated, but reads take lock and allocate output arrays.

### Codex plan

1. **Telemetry storage redesign (lock-free)**

   * Replace `NSLock + MeterSnapshot` with:

     * `ManagedAtomic<UInt64>` sequence number (`metersSeq`)
     * A fixed-size struct stored twice (double buffer) or a single buffer with seqlock pattern.
   * Meter writers:

     * Write new meter values to back buffer, then increment seq.
   * Meter readers:

     * Spin read seq start/end until consistent (bounded attempts).
2. **Scope history redesign**

   * Keep ring buffers preallocated.
   * Store only a downsampled/decimated stream (already bucketizing later); do decimation on RT thread to reduce writes.
   * Provide a non-allocating read API:

     * UI provides a preallocated `[Float]` output buffer.
     * Or return `UnsafeBufferPointer<Float>` view to a snapshot copied on worker thread.
3. **Stop() safety**

   * Ensure `stop()` cannot race with render callback:

     * Set `isShuttingDown = true` (atomic), then stop engine, then dispose buffers.
   * Make `isShuttingDown` an atomic flag to ensure render sees it without locks.
4. **Preallocation**

   * Move all `Array(repeating:)` into initialization or start-time preallocation only.
   * Confirm no `monitorMPXLeftScratch = Array(...)` occurs in callback paths.

### Acceptance

* Static scan: no `NSLock.lock()` reachable from render callback.
* Instruments: no allocations during render callback (Allocations instrument stays flat).

---

## Phase 2 — Split MPXGenerator into RT core + control plane

### Goals

Make `processSample` strictly RT-safe and move all configuration/text/scheduling work out.

### Codex plan

1. **Define `MPXParams` POD**

   * A plain struct of floats/ints describing current config:

     * gains, levels, booleans, crossover frequencies, compressor params, RDS level, etc.
   * Store it in an atomic pointer or double-buffered params snapshot.
2. **RT core object**

   * `MPXGeneratorRT` holds filter states, oscillators, envelope followers, limiter state, ring buffers.
   * Only accepts:

     * `renderBlock(inputL,inputR, outMPX, frameCount)`
     * `applyParamsSnapshot(params)` (called on worker thread, swaps precomputed coeffs safely)
3. **Control plane object**

   * `MPXGeneratorControl`:

     * Parses config, computes biquad coeffs, updates RDS schedules, loads marker content, builds prepared strings, etc.
   * Produces:

     * `MPXParams` snapshots
     * `RDSBitstreamChunk` buffers

### Acceptance

* `MPXGeneratorRT` has no references to `Foundation` types (`Date`, `String`, `URLSession`, `Calendar`, `NSRegularExpression`).
* `processSample` uses only numeric operations and preallocated buffers.

---

## Phase 3 — Re-architect RDS generation to be RT-safe

### Current issues

* `BasicRDSCoder.nextSample*()` can call `nextGroupBits()` which can call:

  * schedule generation using `Date()`
  * text resolution and regex matching indirectly (depending on sequence updates and markers)
  * string slicing and UTF8 conversions
* `loadTextFromURL` uses `DispatchSemaphore` and `URLSession`.

### Codex plan

1. **Two-stage RDS pipeline**

   * **Stage A (control thread)**: build RDS groups → bits → shaped baseband samples.
   * **Stage B (audio thread)**: consume precomputed samples from a ring buffer.
2. **Replace per-sample group building**

   * Control thread runs at e.g. 50–200 Hz cadence:

     * Ensures the RDS sample ring has at least N milliseconds buffered (e.g. 200–500 ms).
   * It generates shaped samples at audio sample rate (or at a lower RDS internal rate resampled) and writes to ring.
3. **Pilot-locked phase**

   * Audio thread provides current pilot phase occasionally via atomic float.
   * Control thread can optionally align subcarrier phase for blocks, but simplest:

     * Audio thread modulates buffered RDS baseband with instantaneous `sin(3*pilotPhase)` (cheap).
     * Buffer stores *shaped symbols* (baseband NRZ biphase waveform), not already-carrier-modulated.
4. **Move all text/regex/file/URL**

   * Marker resolution, `parseRTPlusTags`, timed sequences, UTF8 frames generation: control thread only.
5. **Clock Time (CT)**

   * Control thread inserts CT groups on wall clock boundaries.
   * Audio thread never calls `Date()`.

### Acceptance

* Audio thread RDS work reduces to:

  * read next shaped sample from ring
  * multiply by `sin(3*pilotPhase)` and scale
* No `String`, `Date`, `Calendar`, `URLSession`, `NSRegularExpression` reachable from render.

---

## Phase 4 — Make input capture and resampling deterministic

### Goals

Eliminate any jitter from capture callback, ensure adaptive consumption doesn’t oscillate and cause audible artifacts.

### Codex plan

1. **Ring buffer contract**

   * `StereoInputRingBuffer` must be lock-free and RT safe (single producer tap, single consumer render).
   * Ensure `bufferedFrames()` and `readAdaptive()` are constant-time.
2. **Adaptive read tuning**

   * Document and test `nominalConsume`, `targetBuffered`, `deadband`.
   * Add a slow PI controller (control thread) to adjust `inputToRenderRatio` or `nominalConsume` based on drift instead of per-callback heuristics.
3. **Format conversion**

   * Convert capture formats to float in capture callback using preallocated scratch only.
   * Avoid `Array(repeating:)` in `pushInputBufferToRing` for int16/int32 conversions:

     * Use reusable scratch buffers (`inputConversionBufferStereoL/R`) sized for max tap frameCount.
4. **Priming logic**

   * Keep prefill and reset rules deterministic:

     * If `missing >= frames/4` -> drop back to priming state.

### Acceptance

* No allocations in capture tap.
* Underflow count stays ~0 under steady state with real devices.

---

## Phase 5 — Audio engine graph simplification and mode separation

### Goals

Make `.mpxComposite` and `.monitorAudio` paths share minimal branching in callback and avoid heavy per-frame conditional logic.

### Codex plan

1. **Create two render functions**

   * `renderMPXBlock(...)`
   * `renderMonitorBlock(...)`
2. **Select function pointer/closure once**

   * On start, choose a block renderer based on `useInputSource`, `outputMode`, `processingBypass`.
   * Avoid nested branching per callback.
3. **Monitor path**

   * If monitor requires demod from MPX, ensure demod filters are in RT core and stable.

### Acceptance

* Callback contains one main loop and minimal `if` branching.

---

## Phase 6 — DSP correctness and safety gates

### Codex plan

1. **Unit tests (Swift XCTest)**

   * Biquad stability: impulse response bounded, no NaNs.
   * Preemphasis/deemphasis sanity: DC gain, expected HF slope direction.
   * Limiter: never exceeds threshold, release behaves as expected.
   * RDS:

     * CRC correctness for known vectors
     * group packing sizes
2. **Property tests**

   * Feed random bounded inputs; assert outputs are finite and within [-1, 1].
3. **Level calibration tests**

   * Given 1 kHz stereo tone at known amplitude:

     * pilot amplitude equals config * deviationScale
     * RDS level scale respects rdsLevel/75 and clamp
4. **Regression: stereo protect**

   * Add a test to detect “slow collapse” by measuring L-R energy over 120 seconds synthetic content.

### Acceptance

* All tests pass in CI.
* Long-run simulation produces no NaN/Inf and no drift in stereo metrics unless configured.

---

## Phase 7 — Profiling, metrics, and release hardening

### Codex plan

1. **Instruments templates**

   * Time Profiler: verify callback stays below buffer duration by comfortable margin.
   * Allocations: zero allocations during render/capture.
2. **Runtime self-checks**

   * If render time exceeds X% of buffer duration, increment counter and expose in UI.
   * If underflows exceed threshold, auto-increase target buffer or switch to safer settings.
3. **Crash-proofing**

   * Guard against `frameCount` spikes by ensuring all scratch buffers are sized for max expected frames; clamp and clear if exceeded.

### Acceptance

* Render max time < 30% of buffer duration in typical config.
* Zero allocations in callback confirmed.

---

## Suggested Codex execution order (task list)

1. Create `RealtimeRules.md` + audit list of forbidden calls.
2. Implement atomic telemetry (meters + scope) and remove `NSLock` from callback paths.
3. Refactor RDS into control-thread producer + audio-thread consumer ring.
4. Split MPXGenerator into RT core + control plane; remove Foundation from RT core.
5. Fix capture conversion allocations using reusable scratch.
6. Add tests for DSP and RDS correctness.
7. Profiling hooks + UI counters + safety fallbacks.

---

## Key refactor targets in your code (high priority)

* `BasicRDSCoder.resolveTextMarkers/loadTextFromURL/NSRegularExpression/Date()` must be **control-thread only**.
* `pushInputBufferToRing` must stop allocating `left/right` arrays for int formats.
* `scopeSnapshot()` should avoid lock + allocation; provide preallocated output or snapshot copy done off RT thread.
* Callback branching should be reduced by preselecting a render function at start.

---

If you want Codex to implement this efficiently, paste this plan as the “spec”, then ask it to start with **Phase 1 + Phase 3** first (those remove the largest real-time hazards).
