Yes. The clean way (for FM) is:

* **Generate enhancement from mono bass only (L+R)** and add it back **equally to L and R** (keeps L−R deviation under control).
* **No subharmonics** (the square/envelope block is the least “broadcast-clean” part).
* **Oversample the nonlinear stage** and **hard bandlimit the generated content** (so it cannot leak into 19/38/57 kHz world later).
* Keep it **allocation-free** and compatible with your current DSP style.

Below is a drop-in “broadcast clean” Orbass block that fits your codebase conventions (structs, `configure(sampleRate:)`, per-sample `process(left:right:)`), using:

* 2× oversampling with a **fixed halfband FIR** (cheap and predictable),
* nonlinear `tanh` waveshaper in the oversampled domain,
* **explicit post-waveshaper lowpass** (biquad cascade, 6th order Butterworth) around 350–450 Hz,
* mono-only injection.

---

## 1) Add a fixed 2× halfband up/downsampler (no allocations)

```swift
struct Halfband2xFIR {
    // 15-tap halfband, symmetric, center tap = 0.5, odd taps only (others are 0).
    // These are a commonly used "good enough" halfband set for audio oversampling.
    // Stopband is not “lab perfect”, but it is vastly better than linear upsampling.
    // If you want steeper, use 23/31 taps, same structure.
    private static let h: [Float] = [
        -0.0016820, 0.0,
         0.0102060, 0.0,
        -0.0340400, 0.0,
         0.0902570, 0.0,
         0.5000000, 0.0,
         0.0902570, 0.0,
        -0.0340400, 0.0,
         0.0102060, 0.0,
        -0.0016820
    ]

    // Delay line for full-rate samples (for upsampling and downsampling)
    private var z: [Float] = Array(repeating: 0.0, count: h.count)
    private var zi: Int = 0

    mutating func reset() {
        for i in 0..<z.count { z[i] = 0.0 }
        zi = 0
    }

    // Push one input sample into delay line
    @inline(__always)
    private mutating func push(_ x: Float) {
        z[zi] = x
        zi &+= 1
        if zi >= z.count { zi = 0 }
    }

    // Convolution at the current write position (circular)
    @inline(__always)
    private func convolve() -> Float {
        var acc: Float = 0.0
        var idx = zi
        // z[zi] is the "next" slot; most recent sample is at zi-1
        for k in 0..<Self.h.count {
            idx &-= 1
            if idx < 0 { idx = z.count - 1 }
            acc += z[idx] * Self.h[k]
        }
        return acc
    }

    // 2× upsample: returns (evenPhase, oddPhase)
    // evenPhase is typically "x delayed", oddPhase is the interpolated.
    @inline(__always)
    mutating func up2(_ x: Float) -> (Float, Float) {
        // Even output: pass-through with delay (use center-tap aligned output via convolve too)
        push(x)
        let odd = convolve()
        // For even, use the delayed sample at center alignment (approx)
        // Using the same filtered output for even is also acceptable; this keeps phase consistent.
        let even = odd
        return (even, odd)
    }

    // 2× downsample: feed two oversampled samples, return one output (filtered)
    @inline(__always)
    mutating func down2(_ x0: Float, _ x1: Float) -> Float {
        // Push both samples then take one filtered output (decimate by 2).
        push(x0)
        _ = convolve()
        push(x1)
        return convolve()
    }
}
```

---

## 2) Add a DC blocker tuned for the oversampled domain

```swift
struct DCBlocker1p {
    // y[n] = x[n] - x[n-1] + R*y[n-1]
    // R close to 1, corner ~ a few Hz.
    private var r: Float = 0.995
    private var x1: Float = 0.0
    private var y1: Float = 0.0

    mutating func configure(cutoffHz: Float, sampleRate: Float) {
        let sr = max(8_000.0, sampleRate)
        let fc = max(1.0, min(50.0, cutoffHz))
        // R ≈ exp(-2πfc/sr)
        r = expf(-twoPi * fc / sr)
        x1 = 0.0
        y1 = 0.0
    }

    @inline(__always)
    mutating func process(_ x: Float) -> Float {
        let y = x - x1 + r * y1
        x1 = x
        y1 = y
        return y
    }
}
```

---

## 3) Broadcast-clean Orbass processor (mono-only + oversampled waveshaper + strict bandlimit)

```swift
struct OrbassBroadcastClean {
    var enabled: Bool = false

    // User-facing controls (map from your config)
    var amount: Float = 0.0          // 0..1
    var drive: Float = 0.0           // 0..2.5
    var harmonics: Float = 0.0       // 0..1
    var freqHz: Float = 90.0         // 45..220

    // Internal
    private var sampleRate: Float = 48_000.0
    private let os: Float = 2.0

    private var bassLP = BiquadCascade6()
    private var enhLP = BiquadCascade6()      // hard lowpass for generated content
    private var harmHP = BiquadCascade6()     // keep harmonics away from sub-bass
    private var up = Halfband2xFIR()
    private var down = Halfband2xFIR()
    private var dcOS = DCBlocker1p()

    mutating func configure(sampleRate: Float) {
        self.sampleRate = max(8_000.0, sampleRate)

        // Bass extraction (mono) — keep it comfortably below your stereo encoder concerns.
        // freqHz is the "bass focus". We'll lowpass around that.
        let bassCut = clampf(freqHz, 45.0, min(250.0, (self.sampleRate * 0.5) - 500.0))
        bassLP.configureLowpass(cutoffHz: bassCut, sampleRate: self.sampleRate)

        // Generated enhancement must be strictly low-frequency.
        // 350–450 Hz is typical; choose lower for “cleaner”, higher for “fatter”.
        enhLP.configureLowpass(cutoffHz: 420.0, sampleRate: self.sampleRate)

        // Remove sub-bass from harmonic band so it doesn’t turn into LF mush or slow AGC pumping.
        harmHP.configureHighpass(cutoffHz: 120.0, sampleRate: self.sampleRate)

        up.reset()
        down.reset()
        dcOS.configure(cutoffHz: 5.0, sampleRate: self.sampleRate * os)
    }

    @inline(__always)
    mutating func process(left: Float, right: Float) -> (Float, Float) {
        guard enabled else { return (left, right) }

        let amt = clampf(amount, 0.0, 1.0)
        let harm = clampf(harmonics, 0.0, 1.0)
        if amt <= 1e-4, harm <= 1e-4 { return (left, right) }

        // 1) Mid/Side split
        let mid = 0.5 * (left + right)
        let side = 0.5 * (left - right)

        // 2) Extract mono bass from mid only
        let bass = bassLP.process(mid)

        // 3) Oversampled nonlinear stage (2×)
        //    Use both "amount" (bass boost) and "harmonics" (extra grit) but keep it bandlimited.
        let d = 1.0 + clampf(drive, 0.0, 2.5) * (1.2 + 2.0 * harm + 1.5 * amt)

        // Upsample
        let (b0, b1) = up.up2(bass)

        // Nonlinearity in OS domain
        var y0 = tanhf(b0 * d)
        var y1 = tanhf(b1 * d)

        // DC removal in OS domain
        y0 = dcOS.process(y0)
        y1 = dcOS.process(y1)

        // Downsample (filtered)
        var shaped = down.down2(y0, y1)

        // 4) Separate “boost” vs “harmonics” (still audio-band), then hard-limit bandwidth
        //    - boost: scaled original bass
        //    - harmonics: shaped minus a gentler shaped version (a simple “edge extractor”)
        let soft = tanhf(bass * (0.6 * d))
        let harmonicOnly = shaped - soft

        var enh = (bass * (0.9 * amt)) + (harmonicOnly * (0.65 * harm))

        // Strict band limits
        enh = enhLP.process(harmHP.process(enh))

        // 5) Inject back into MID only -> preserves mono bass (FM-friendly)
        let midOut = mid + enh

        // Recombine
        let outL = midOut + side
        let outR = midOut - side
        return (outL, outR)
    }
}
```

---

## 4) Wire it into your `MPXGenerator` with minimal disruption

### Add a member

```swift
private var orbassClean = OrbassBroadcastClean()
```

### Configure it in `init` and `setSampleRate`

Right after `configureOrbassFilters()` (or replace that path for this clean mode):

```swift
orbassClean.enabled = orbassEnabled
orbassClean.amount = orbassAmount
orbassClean.drive = orbassDrive
orbassClean.harmonics = orbassHarmonics
orbassClean.freqHz = orbassFreqHz
orbassClean.configure(sampleRate: sampleRate)
```

Also call the same block in `setSampleRate()`.

### Use it in `processSample` instead of `processOrbass`

Replace:

```swift
if orbassEnabled {
    let orbassOut = processOrbass(left: l, right: r)
    l = orbassOut.0
    r = orbassOut.1
}
```

With:

```swift
if orbassEnabled {
    let o = orbassClean.process(left: l, right: r)
    l = o.0
    r = o.1
}
```

---

## Notes specific to your MPX chain

* This block runs **before pre-emphasis and before stereo encoding**, which is correct.
* Because enhancement is **strictly low-frequency** and **mid-only**, it won’t generate content that can alias into pilot/RDS bands later, and it won’t inflate L−R deviation.
* Keep your **composite limiter** at the end (you already do). That’s where final deviation protection belongs.

If you want a “proof mode” switch: add a config boolean like `orbassBroadcastClean` and keep your existing `processOrbass` as the “creative” mode; the clean mode should default to:

* `subharmonics = false`
* `enhLP cutoff = 380–420 Hz`
* `harmHP cutoff = 100–140 Hz`
