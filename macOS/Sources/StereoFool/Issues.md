Issues 

## Likely functional / DSP issues

### 1) RDS is **not actually phase-locked to your MPX pilot**

`nextSampleWithPilotLock()` advances its own `pilotPhaseForRDS` using `pilotStepForRDS`, but `MPXGenerator` never calls `rdsCoder.updateRDSPilotPhase(pilotPhase)` (or otherwise shares the generator’s pilot phase). So you have *two independent 19 kHz oscillators*:

* MPX pilot: `pilotPhase`
* RDS “pilot lock”: `pilotPhaseForRDS`

Even if both run at nominal 19 kHz, they will not stay phase-aligned (different start phase, potential sample-rate change timing, etc.). That can show up as extra skirt/“thickness” around 57 kHz or a less clean spectrum.

**Fix (cheap and effective):**
In `processSample`, before generating RDS, feed the current pilot phase:

```swift
rdsCoder?.updateRDSPilotPhase(pilotPhase)
let rds = rdsSupported ? (rdsCoder?.nextSampleWithPilotLock() ?? 0.0) : 0.0
```

And in `BasicRDSCoder.nextSampleWithPilotLock()` remove the internal `pilotPhaseForRDS += pilotStepForRDS` (or keep it only as fallback if not externally driven).

---

### 2) Preemphasis is applied only to the **sum** path, not to L/R (or not equally to sum/diff)

You do:

```swift
var base = ((l + r) * 0.5) * sumLevel
let diff = (((r - l) * 0.5) * diffLevel)
base = preSum.process(base)
// diff preemphasis disabled
```

In real FM stereo, preemphasis is applied to L and R equally **before** the stereo coder (or equivalently applied to both sum and diff with matched response/state). Applying it to sum only will tilt stereo HF behavior and can affect separation and perceived image at high frequencies.

The comment about `lpState drift` and stereo collapsing suggests your `PreemphasisFilter` implementation/state handling is the real bug, not that preemphasis belongs only on sum.

**Correct approach:**

* Apply preemphasis to **L and R individually**, then form sum/diff.

  * This avoids “sum-only preemphasis” artifacts and keeps stereo consistent.

---

### 3) `PreemphasisFilter` is not a standard preemphasis, and its gain calibration is odd

This implementation:

* Lowpasses input into `lpState`
* Takes `hp = x - lpState`
* Returns `x + hp * shelfGain`
* `shelfGain` is derived from a reference at 15 kHz and a tau.

This behaves like an approximate shelving boost, but FM preemphasis is a well-defined 1st-order high-frequency boost with time constant (50/75 µs). Your “reference at 15 kHz” calibration is arbitrary and will not match the standard curve tightly.

If you want predictable deviation/spectrum behavior, implement true preemphasis as a 1st-order IIR using standard difference equation (or bilinear transform), not an ad-hoc shelf.

---

### 4) Subcarrier generation contradicts your own “no fmodf” comment (and wastes `subStep`)

You compute:

```swift
pilotPhase += pilotStep
subPhase = fmodf(2.0 * pilotPhase, twoPi)
```

* This calls `fmodf` every sample (expensive).
* `subStep` is computed but never used.
* If you want *phase-locked* 38 kHz, you can avoid `fmodf` by wrapping `pilotPhase` and deriving `subPhase` with a conditional wrap too, or just run a 38 kHz NCO and hard-correct phase occasionally.

At minimum, if `pilotPhase` is always wrapped into `[0, 2π)`, then `2*pilotPhase` is in `[0, 4π)` and you can wrap with a single compare:

```swift
subPhase = 2.0 * pilotPhase
if subPhase >= twoPi { subPhase -= twoPi }
```

---

### 5) RDS level scaling is easy to overshoot

You set:

```swift
levelScale = clampf(Float(config.rdsLevel) / 75.0, 0.0, 0.25)
```

If `rdsLevel == 75`, that’s **0.25 amplitude** *before* adding into MPX and before deviation scaling. That is often too hot, and it will thicken the 57 kHz region (like your screenshot shows: the 57 kHz block looks relatively high and wide).

Typical composite RDS injection is kept modest relative to pilot and program; if your spectrum shows RDS close to the L–R region, it’s probably high.

---

### 6) Your monitor stereo demod depends on the generator’s `lastSubcarrierSample`

In `demodulateMonitorFromMPXSample` you do:

```swift
var diff = 2.0 * dsb * lastSubcarrierSample
```

This only works if:

* the MPX being demodulated was produced by the same generator instance in perfect lockstep.

If you ever use the monitor demod on an external MPX stream, it will fail. Even internally, it’s fragile to block boundaries if you move work off the real-time thread. A proper monitor demod should recover 19 kHz with a PLL and synthesize 38 kHz from it.

---

## Likely “engineering” issues that can bite you

### 7) Sample-rate changes: RDS shaping kernels rebuild, but phase alignment can jump

`setSampleRate()` in `BasicRDSCoder` rebuilds shaping filters and derived rates, but your externally visible MPX pilot phase is not coordinated with the RDS phase (see #1). After SR changes, phase discontinuities can create audible clicks in demodulated monitor and visible splatter.

---

### 8) Limiter placement and scaling can generate composite splatter

You do:

```swift
mpx = (base + (diff * sub) + pilot + rds) * deviationScale
if limitEnabled { ... softClipSafety ... }
mpx *= outputGain
clamp
```

If `deviationScale` is near 1.0 and base/diff/pilot/rds sum exceeds threshold often, you will clip composite—not just audio—creating broadband energy (including in 0–15 kHz and between stereo components). That matches the general “filled” look in parts of the spectrum.

If your goal is FM-safe loudness:

* limit/compress audio **before** stereo coder and preemphasis,
* then use a composite limiter only as a final safety net.

---

## What I would change first (highest ROI)

1. **Truly lock RDS to the MPX pilot phase** (share `pilotPhase`).
2. Replace `PreemphasisFilter` with a standard 50/75 µs IIR and apply it to **L/R** (or both sum+diff with matched response).
3. Reduce and calibrate **pilot and RDS injection** (your spectrum suggests RDS is hot).
4. Remove per-sample `fmodf` for the subcarrier wrap.

If you want, paste the code that sets `pilotLevel`, `sumLevel`, `diffLevel`, `rdsLevel`, and `mpxDeviationKHz` (your `AppConfig` values). That’s enough to sanity-check why your spectrum looks the way it does.
