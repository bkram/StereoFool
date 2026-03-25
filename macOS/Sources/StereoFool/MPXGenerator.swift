import Darwin
import Foundation

private let twoPi = Float.pi * 2.0
private let pilotFreq = Float(19_000.0)
private let subcarrierFreq = Float(38_000.0)

@inline(__always)
private func clampf(_ x: Float, _ lo: Float, _ hi: Float) -> Float {
    return max(lo, min(hi, x))
}

@inline(__always)
private func lerpf(_ a: Float, _ b: Float, _ t: Float) -> Float {
    return a + ((b - a) * t)
}

@inline(__always)
private func zapDenorm(_ x: Float) -> Float {
    return (fabsf(x) < 1e-20) ? 0.0 : x
}

struct SineCosOsc {
    var s: Float = 0.0
    var c: Float = 1.0
    var phase: Float = 0.0
    private var sinInc: Float = 0.0
    private var cosInc: Float = 1.0
    private var stepPhase: Float = 0.0
    private var renormCounter: Int = 0

    init() {}

    mutating func configure(freq: Float, sampleRate: Float) {
        let w = twoPi * freq / sampleRate
        stepPhase = w
        sinInc = sinf(w)
        cosInc = cosf(w)
        s = 0.0
        c = 1.0
        phase = 0.0
        renormCounter = 0
    }

    @inline(__always) mutating func step() {
        let ns = s * cosInc + c * sinInc
        let nc = c * cosInc - s * sinInc
        s = ns
        c = nc

        phase += stepPhase
        if phase >= twoPi { phase -= twoPi }

        renormCounter &+= 1
        if (renormCounter & 1023) == 0 {
            let mag2 = s * s + c * c
            if mag2 > 0 {
                let invMag = 1.0 / sqrtf(mag2)
                s *= invMag
                c *= invMag
            }
        }
    }

    @inline(__always) mutating func sin2x() -> Float {
        return 2.0 * s * c
    }
}

struct DCBlocker1p {
    private var r: Float = 0.995
    private var x1: Float = 0.0
    private var y1: Float = 0.0

    mutating func configure(cutoffHz: Float, sampleRate: Float) {
        let sr = max(8_000.0, sampleRate)
        let fc = max(1.0, min(50.0, cutoffHz))
        r = expf(-twoPi * fc / sr)
        x1 = 0.0
        y1 = 0.0
    }

    @inline(__always)
    mutating func process(_ x: Float) -> Float {
        let y = x - x1 + r * y1
        x1 = x
        y1 = zapDenorm(y)
        return y
    }
}

struct CompositeTruePeakLimiter {
    var threshold: Float = 0.94
    var releaseMS: Float = 35.0
    var ceiling: Float = 0.985

    private var gain: Float = 1.0
    private var attackCoeff: Float = 0.0
    private var releaseCoeff: Float = 0.0
    private var holdSamples: Int = 0
    private var holdCounter: Int = 0
    private var prevPrevPrevIn: Float = 0.0
    private var prevPrevIn: Float = 0.0
    private var prevIn: Float = 0.0
    private var decimationLP = BiquadCascade6()
    private var initialized: Bool = false

    mutating func configure(sampleRate: Float, threshold: Float, releaseMS: Float = 35.0) {
        let sr = max(8_000.0, sampleRate * 4.0)
        self.threshold = clampf(threshold, 0.75, 0.995)
        self.releaseMS = max(8.0, releaseMS)
        let ceilingMargin = max(0.012, (1.0 - self.threshold) * 0.65)
        ceiling = min(0.999, self.threshold + ceilingMargin)

        let attackS = 0.00025 as Float
        let relS = max(0.008, Double(self.releaseMS) * 0.001)
        attackCoeff = expf(-1.0 / (attackS * sr))
        releaseCoeff = expf(-1.0 / Float(relS * Double(sr)))
        holdSamples = max(1, Int((0.004 * sr).rounded()))
        holdCounter = 0
        gain = 1.0
        prevPrevPrevIn = 0.0
        prevPrevIn = 0.0
        prevIn = 0.0
        let cutoff = min(sampleRate * 0.30, (sr * 0.5) - 1_000.0)
        decimationLP.configureLowpass(cutoffHz: max(12_000.0, cutoff), sampleRate: sr)
        initialized = false
    }

    mutating func process(_ x: Float) -> Float {
        if !initialized {
            initialized = true
            prevPrevPrevIn = x
            prevPrevIn = x
            prevIn = x
            let q = processStep(x)
            return decimate(q1: q, q2: q, q3: q, q4: q)
        }

        let q1 = processStep(interpolateLagrange4(t: 0.25, current: x))
        let q2 = processStep(interpolateLagrange4(t: 0.50, current: x))
        let q3 = processStep(interpolateLagrange4(t: 0.75, current: x))
        let q4 = processStep(x)
        let output = decimate(q1: q1, q2: q2, q3: q3, q4: q4)

        prevPrevPrevIn = prevPrevIn
        prevPrevIn = prevIn
        prevIn = x
        return output
    }

    var gainReductionDB: Float {
        let safeGain = max(1e-6, gain)
        return max(0.0, -20.0 * log10f(safeGain))
    }

    @inline(__always)
    private mutating func processStep(_ x: Float) -> Float {
        let peak = fabsf(x)

        var targetGain: Float = 1.0
        if peak > threshold {
            targetGain = threshold / max(1e-9, peak)
        }
        targetGain = clampf(targetGain, 0.0, 1.0)

        if targetGain < gain {
            gain = (attackCoeff * gain) + ((1.0 - attackCoeff) * targetGain)
            holdCounter = holdSamples
        } else if holdCounter > 0 {
            holdCounter -= 1
        } else {
            gain = (releaseCoeff * gain) + ((1.0 - releaseCoeff) * targetGain)
        }

        let y = x * gain
        return clipToCeiling(y)
    }

    @inline(__always)
    private func interpolateLagrange4(t: Float, current: Float) -> Float {
        // Causal 4-point reconstruction between prevIn and current using
        // two prior samples for better curvature tracking.
        let l0 = -((t + 1.0) * t * (t - 1.0)) / 6.0
        let l1 = ((t + 2.0) * t * (t - 1.0)) * 0.5
        let l2 = -((t + 2.0) * (t + 1.0) * (t - 1.0)) * 0.5
        let l3 = ((t + 2.0) * (t + 1.0) * t) / 6.0
        return (prevPrevPrevIn * l0) + (prevPrevIn * l1) + (prevIn * l2) + (current * l3)
    }

    @inline(__always)
    private mutating func decimate(q1: Float, q2: Float, q3: Float, q4: Float) -> Float {
        _ = decimationLP.process(q1)
        _ = decimationLP.process(q2)
        _ = decimationLP.process(q3)
        return decimationLP.process(q4)
    }

    @inline(__always)
    private func clipToCeiling(_ x: Float) -> Float {
        let ax = fabsf(x)
        if ax <= threshold { return x }

        let knee = max(1e-4, ceiling - threshold)
        let clipped = threshold + ((ceiling - threshold) * tanhf((ax - threshold) / knee))
        return copysignf(min(clipped, ceiling), x)
    }
}

struct OnePoleLP {
    var alpha: Float = 1.0
    var state: Float = 0.0

    mutating func configure(cutoffHz: Float, sampleRate: Float) {
        let fc = max(8.0, min(45_000.0, cutoffHz))
        let sr = max(8_000.0, sampleRate)
        let pole = expf(-twoPi * fc / sr)
        alpha = clampf(1.0 - pole, 0.0, 1.0)
    }

    mutating func process(_ x: Float) -> Float {
        state += alpha * (x - state)
        state = zapDenorm(state)
        return state
    }
}

struct Biquad {
    var b0: Float = 1.0
    var b1: Float = 0.0
    var b2: Float = 0.0
    var a1: Float = 0.0
    var a2: Float = 0.0
    var z1: Float = 0.0
    var z2: Float = 0.0

    mutating func reset() {
        z1 = 0.0
        z2 = 0.0
    }

    mutating func configureIdentity() {
        b0 = 1.0
        b1 = 0.0
        b2 = 0.0
        a1 = 0.0
        a2 = 0.0
        reset()
    }

    mutating func configureLowpass(cutoffHz: Float, sampleRate: Float, q: Float = 0.7071068) {
        let sr = max(8_000.0, sampleRate)
        let nyquist = (sr * 0.5) - 10.0
        let fc = clampf(cutoffHz, 8.0, max(16.0, nyquist))
        let w0 = twoPi * fc / sr
        let c = cosf(w0)
        let s = sinf(w0)
        let alpha = s / (2.0 * max(0.1, q))

        let pb0 = (1.0 - c) * 0.5
        let pb1 = 1.0 - c
        let pb2 = (1.0 - c) * 0.5
        let pa0 = 1.0 + alpha
        let pa1 = -2.0 * c
        let pa2 = 1.0 - alpha
        setNormalized(pb0, pb1, pb2, pa0, pa1, pa2)
    }

    mutating func configureHighpass(cutoffHz: Float, sampleRate: Float, q: Float = 0.7071068) {
        let sr = max(8_000.0, sampleRate)
        let nyquist = (sr * 0.5) - 10.0
        let fc = clampf(cutoffHz, 8.0, max(16.0, nyquist))
        let w0 = twoPi * fc / sr
        let c = cosf(w0)
        let s = sinf(w0)
        let alpha = s / (2.0 * max(0.1, q))

        let pb0 = (1.0 + c) * 0.5
        let pb1 = -(1.0 + c)
        let pb2 = (1.0 + c) * 0.5
        let pa0 = 1.0 + alpha
        let pa1 = -2.0 * c
        let pa2 = 1.0 - alpha
        setNormalized(pb0, pb1, pb2, pa0, pa1, pa2)
    }

    mutating func configureNotch(freqHz: Float, sampleRate: Float, q: Float = 12.0) {
        let sr = max(8_000.0, sampleRate)
        let nyquist = (sr * 0.5) - 10.0
        let f0 = clampf(freqHz, 8.0, max(16.0, nyquist))
        let w0 = twoPi * f0 / sr
        let c = cosf(w0)
        let s = sinf(w0)
        let alpha = s / (2.0 * max(0.1, q))

        let pb0: Float = 1.0
        let pb1: Float = -2.0 * c
        let pb2: Float = 1.0
        let pa0: Float = 1.0 + alpha
        let pa1: Float = -2.0 * c
        let pa2: Float = 1.0 - alpha
        setNormalized(pb0, pb1, pb2, pa0, pa1, pa2)
    }

    mutating func configureHighShelf(
        gainDB: Float, cutoffHz: Float, sampleRate: Float, slope: Float = 1.0
    ) {
        if fabsf(gainDB) < 0.01 {
            configureIdentity()
            return
        }
        let sr = max(8_000.0, sampleRate)
        let nyquist = (sr * 0.5) - 200.0
        let fc = clampf(cutoffHz, 500.0, max(520.0, nyquist))
        let w0 = twoPi * fc / sr
        let c = cosf(w0)
        let s = sinf(w0)
        let A = powf(10.0, gainDB / 40.0)
        let invA = 1.0 / max(1e-6, A)
        let slopeSafe = max(0.1, slope)
        let alphaTerm = max(0.0, ((A + invA) * ((1.0 / slopeSafe) - 1.0)) + 2.0)
        let alpha = (s * 0.5) * sqrtf(alphaTerm)
        let sqrtA = sqrtf(max(1e-6, A))

        let pb0 = A * ((A + 1.0) + ((A - 1.0) * c) + (2.0 * sqrtA * alpha))
        let pb1 = -2.0 * A * ((A - 1.0) + ((A + 1.0) * c))
        let pb2 = A * ((A + 1.0) + ((A - 1.0) * c) - (2.0 * sqrtA * alpha))
        let pa0 = (A + 1.0) - ((A - 1.0) * c) + (2.0 * sqrtA * alpha)
        let pa1 = 2.0 * ((A - 1.0) - ((A + 1.0) * c))
        let pa2 = (A + 1.0) - ((A - 1.0) * c) - (2.0 * sqrtA * alpha)
        setNormalized(pb0, pb1, pb2, pa0, pa1, pa2)
    }

    mutating func process(_ x: Float) -> Float {
        let y = (b0 * x) + z1
        z1 = (b1 * x) - (a1 * y) + z2
        z2 = (b2 * x) - (a2 * y)
        z1 = zapDenorm(z1)
        z2 = zapDenorm(z2)
        return y
    }

    private mutating func setNormalized(
        _ pb0: Float,
        _ pb1: Float,
        _ pb2: Float,
        _ pa0: Float,
        _ pa1: Float,
        _ pa2: Float
    ) {
        let a0 = fabsf(pa0) < 1e-8 ? 1.0 : pa0
        b0 = pb0 / a0
        b1 = pb1 / a0
        b2 = pb2 / a0
        a1 = pa1 / a0
        a2 = pa2 / a0
        reset()
    }
}

struct StereoBiquad {
    var left = Biquad()
    var right = Biquad()

    mutating func configureHighpass(cutoffHz: Float, sampleRate: Float) {
        left.configureHighpass(cutoffHz: cutoffHz, sampleRate: sampleRate)
        right.configureHighpass(cutoffHz: cutoffHz, sampleRate: sampleRate)
    }

    mutating func configureHighShelf(gainDB: Float, cutoffHz: Float, sampleRate: Float) {
        left.configureHighShelf(gainDB: gainDB, cutoffHz: cutoffHz, sampleRate: sampleRate)
        right.configureHighShelf(gainDB: gainDB, cutoffHz: cutoffHz, sampleRate: sampleRate)
    }

    mutating func process(left: Float, right: Float) -> (Float, Float) {
        return (self.left.process(left), self.right.process(right))
    }
}

struct LinkwitzRiley4 {
    private var lp1 = Biquad()
    private var lp2 = Biquad()
    private var hp1 = Biquad()
    private var hp2 = Biquad()

    mutating func configure(cutoffHz: Float, sampleRate: Float) {
        lp1.configureLowpass(cutoffHz: cutoffHz, sampleRate: sampleRate)
        lp2.configureLowpass(cutoffHz: cutoffHz, sampleRate: sampleRate)
        hp1.configureHighpass(cutoffHz: cutoffHz, sampleRate: sampleRate)
        hp2.configureHighpass(cutoffHz: cutoffHz, sampleRate: sampleRate)
    }

    mutating func process(_ x: Float) -> (low: Float, high: Float) {
        let low = lp2.process(lp1.process(x))
        let high = hp2.process(hp1.process(x))
        return (low, high)
    }
}

struct StereoLinkwitzRiley4 {
    private var left = LinkwitzRiley4()
    private var right = LinkwitzRiley4()

    mutating func configure(cutoffHz: Float, sampleRate: Float) {
        left.configure(cutoffHz: cutoffHz, sampleRate: sampleRate)
        right.configure(cutoffHz: cutoffHz, sampleRate: sampleRate)
    }

    mutating func process(left: Float, right: Float) -> ((Float, Float), (Float, Float)) {
        (self.left.process(left), self.right.process(right))
    }
}

struct BiquadCascade6 {
    private static let butterworthQ: (Float, Float, Float) = (0.5176381, 0.7071068, 1.9318517)
    var s1 = Biquad()
    var s2 = Biquad()
    var s3 = Biquad()

    mutating func configureIdentity() {
        s1.configureIdentity()
        s2.configureIdentity()
        s3.configureIdentity()
    }

    mutating func configureLowpass(cutoffHz: Float, sampleRate: Float) {
        let q = Self.butterworthQ
        s1.configureLowpass(cutoffHz: cutoffHz, sampleRate: sampleRate, q: q.0)
        s2.configureLowpass(cutoffHz: cutoffHz, sampleRate: sampleRate, q: q.1)
        s3.configureLowpass(cutoffHz: cutoffHz, sampleRate: sampleRate, q: q.2)
    }

    mutating func configureHighpass(cutoffHz: Float, sampleRate: Float) {
        let q = Self.butterworthQ
        s1.configureHighpass(cutoffHz: cutoffHz, sampleRate: sampleRate, q: q.0)
        s2.configureHighpass(cutoffHz: cutoffHz, sampleRate: sampleRate, q: q.1)
        s3.configureHighpass(cutoffHz: cutoffHz, sampleRate: sampleRate, q: q.2)
    }

    mutating func process(_ x: Float) -> Float {
        return s3.process(s2.process(s1.process(x)))
    }
}

struct ProgramLowpass {
    var left = BiquadCascade6()
    var right = BiquadCascade6()

    mutating func configure(cutoffHz: Float, sampleRate: Float) {
        left.configureLowpass(cutoffHz: cutoffHz, sampleRate: sampleRate)
        right.configureLowpass(cutoffHz: cutoffHz, sampleRate: sampleRate)
    }

    mutating func process(left: Float, right: Float) -> (Float, Float) {
        let l = self.left.process(left)
        let r = self.right.process(right)
        return (l, r)
    }
}

@inline(__always)
private func effectiveProgramLowpassHz(configured: Float, preemphasisUS: Int) -> Float {
    guard preemphasisUS > 0 else { return configured }
    let complianceCap: Float = preemphasisUS <= 50 ? 15_300.0 : 15_000.0
    return min(configured, complianceCap)
}

@inline(__always)
private func effectiveEncoderLowpassHz(configured: Float, preemphasisUS: Int) -> Float {
    guard preemphasisUS > 0 else { return configured }
    let encoderCap: Float = preemphasisUS <= 50 ? 14_900.0 : 14_600.0
    return min(configured, encoderCap)
}

struct PreemphasisFilter {
    var enabled: Bool = false
    private var a: Float = 0.0
    private var invOneMinusA: Float = 1.0
    private var x1: Float = 0.0

    mutating func configure(tauUS: Int, sampleRate: Float) {
        guard tauUS > 0 else {
            enabled = false
            a = 0.0
            invOneMinusA = 1.0
            x1 = 0.0
            return
        }
        enabled = true
        let sr = max(8_000.0 as Float, sampleRate)
        let tau = Float(tauUS) * 1e-6
        a = expf(-1.0 / (tau * sr))
        invOneMinusA = 1.0 / max(1e-9, (1.0 - a))
        x1 = 0.0
    }

    mutating func process(_ x: Float) -> Float {
        guard enabled else { return x }
        let y = (x - a * x1) * invOneMinusA
        x1 = zapDenorm(x)
        return y
    }

    mutating func reset() { x1 = 0.0 }
}

struct DeemphasisFilter {
    var enabled: Bool = false
    private var a: Float = 0.0
    private var y1: Float = 0.0

    mutating func configure(tauUS: Int, sampleRate: Float) {
        guard tauUS > 0 else {
            enabled = false
            a = 0.0
            y1 = 0.0
            return
        }
        enabled = true
        let sr = max(8_000.0 as Float, sampleRate)
        let tau = Float(tauUS) * 1e-6
        a = expf(-1.0 / (tau * sr))
        y1 = 0.0
    }

    mutating func process(_ x: Float) -> Float {
        guard enabled else { return x }
        let y = (1.0 - a) * x + a * y1
        y1 = zapDenorm(y)
        return y
    }

    mutating func reset() { y1 = 0.0 }
}

struct EnvelopeFollower {
    var attackCoeff: Float = 0.0
    var releaseCoeff: Float = 0.0
    var value: Float = 0.0

    mutating func configure(sampleRate: Float, attackMS: Float, releaseMS: Float) {
        let sr = max(8_000.0, sampleRate)
        let a = max(0.1, attackMS) * 0.001
        let r = max(1.0, releaseMS) * 0.001
        attackCoeff = expf(-1.0 / (a * sr))
        releaseCoeff = expf(-1.0 / (r * sr))
    }

    mutating func processAbs(_ x: Float) -> Float {
        let ax = fabsf(x)
        if ax > value {
            value = (attackCoeff * value) + ((1.0 - attackCoeff) * ax)
        } else {
            value = (releaseCoeff * value) + ((1.0 - releaseCoeff) * ax)
        }
        value = zapDenorm(value)
        return value
    }
}

struct WidebandAGCRider {
    private var detectorAttackCoeff: Float = 0.0
    private var detectorReleaseCoeff: Float = 0.0
    private var attackCoeff: Float = 0.0
    private var releaseCoeff: Float = 0.0
    private var fastMakeupCoeff: Float = 0.0
    private var gateReleaseCoeff: Float = 0.0

    private var targetDB: Float = -20.0
    private var minGainDB: Float = -12.0
    private var maxGainDB: Float = 12.0
    private var windowDB: Float = 1.5
    private var gateThresholdDB: Float = -42.0
    private var makeupThresholdDB: Float = -30.0

    private var power: Float = 0.0
    private var gainDB: Float = 0.0
    private var gateActive: Bool = false

    mutating func configure(
        sampleRate: Float,
        targetDB: Float,
        attackMS: Float,
        releaseMS: Float,
        minGainDB: Float,
        maxGainDB: Float
    ) {
        let sr = max(8_000.0, sampleRate)
        let detectorAttackS = max(0.005, min(Double(attackMS) * 0.001 * 0.35, 0.050))
        let detectorReleaseS = max(0.120, Double(releaseMS) * 0.001 * 0.60)
        detectorAttackCoeff = expf(-1.0 / Float(detectorAttackS * Double(sr)))
        detectorReleaseCoeff = expf(-1.0 / Float(detectorReleaseS * Double(sr)))

        let attackS = max(0.010, Double(attackMS) * 0.001)
        let releaseS = max(0.250, Double(releaseMS) * 0.001)
        let fastMakeupS = max(0.120, min(releaseS * 0.35, 0.450))
        attackCoeff = expf(-1.0 / Float(attackS * Double(sr)))
        releaseCoeff = expf(-1.0 / Float(releaseS * Double(sr)))
        fastMakeupCoeff = expf(-1.0 / Float(fastMakeupS * Double(sr)))
        gateReleaseCoeff = expf(-1.0 / Float(1.6 * Double(sr)))

        self.targetDB = targetDB
        self.minGainDB = minGainDB
        self.maxGainDB = maxGainDB
        self.windowDB = 3.0
        self.gateThresholdDB = targetDB - maxGainDB - 10.0
        self.makeupThresholdDB = targetDB - maxGainDB + 2.0
    }

    mutating func process(left: Float, right: Float) -> (Float, Float) {
        let monoPower = max(1e-12, 0.5 * ((left * left) + (right * right)))
        let detectorCoeff = monoPower > power ? detectorAttackCoeff : detectorReleaseCoeff
        power = (detectorCoeff * power) + ((1.0 - detectorCoeff) * monoPower)
        power = zapDenorm(power)

        let levelDB = 10.0 * log10f(max(power, 1e-12))
        let desiredGainDB = clampf(targetDB - levelDB, minGainDB, maxGainDB)

        let targetGainDB: Float
        let coeff: Float
        if levelDB < gateThresholdDB {
            // Do not lift room noise or codec hash; drift back toward unity instead.
            targetGainDB = 0.0
            coeff = gateReleaseCoeff
            gateActive = true
        } else if fabsf(desiredGainDB - gainDB) <= windowDB {
            targetGainDB = gainDB
            coeff = 1.0
            gateActive = false
        } else if desiredGainDB < gainDB {
            targetGainDB = desiredGainDB
            coeff = attackCoeff
            gateActive = false
        } else {
            targetGainDB = desiredGainDB
            coeff = levelDB < makeupThresholdDB ? fastMakeupCoeff : releaseCoeff
            gateActive = false
        }

        gainDB = (coeff * gainDB) + ((1.0 - coeff) * targetGainDB)
        gainDB = clampf(gainDB, minGainDB, maxGainDB)

        let gain = powf(10.0, gainDB / 20.0)
        return (left * gain, right * gain)
    }

    mutating func reset() {
        power = 0.0
        gainDB = 0.0
        gateActive = false
    }

    var telemetry: (detectorDB: Float, gainDB: Float, gateActive: Bool) {
        let detectorDB = 10.0 * log10f(max(power, 1e-12))
        return (detectorDB, gainDB, gateActive)
    }
}

struct MonoCompressor {
    var thresholdDB: Float = -18.0
    var ratio: Float = 2.0
    var makeupDB: Float = 0.0
    var kneeDB: Float = 0.0
    var detector = EnvelopeFollower()

    mutating func configure(
        sampleRate: Float,
        thresholdDB: Float,
        ratio: Float,
        attackMS: Float,
        releaseMS: Float,
        makeupDB: Float,
        kneeDB: Float = 0.0
    ) {
        self.thresholdDB = thresholdDB
        self.ratio = max(1.0, ratio)
        self.makeupDB = makeupDB
        self.kneeDB = max(0.0, min(12.0, kneeDB))
        detector.configure(sampleRate: sampleRate, attackMS: attackMS, releaseMS: releaseMS)
    }

    mutating func process(_ x: Float, sidechainAbs: Float? = nil) -> Float {
        let detectorSample = sidechainAbs ?? x
        let env = max(1e-8, detector.processAbs(detectorSample))
        let levelDB = 20.0 * log10f(env)
        let gainDB = gainReductionDB(for: levelDB)
        let gain = powf(10.0, (gainDB + makeupDB) / 20.0)
        return x * gain
    }

    private func gainReductionDB(for levelDB: Float) -> Float {
        if ratio <= 1.0 {
            return 0.0
        }
        let kneeHalf = kneeDB * 0.5
        if kneeDB <= 0.01 {
            if levelDB <= thresholdDB {
                return 0.0
            }
            let over = levelDB - thresholdDB
            return -(over - (over / ratio))
        }

        let lower = thresholdDB - kneeHalf
        let upper = thresholdDB + kneeHalf
        if levelDB <= lower {
            return 0.0
        }
        if levelDB >= upper {
            let over = levelDB - thresholdDB
            return -(over - (over / ratio))
        }
        let delta = levelDB - lower
        let curve = ((1.0 / ratio) - 1.0) * ((delta * delta) / (2.0 * max(1e-4, kneeDB)))
        return curve
    }
}

struct LookaheadLimiter {
    var enabled: Bool = false
    var threshold: Float = 0.98
    var lookaheadSamples: Int = 0
    var delayLine: [Float] = []
    var writeIndex: Int = 0
    var gain: Float = 1.0
    var attackCoeff: Float = 0.0
    var releaseCoeff: Float = 0.0
    var holdSamples: Int = 0
    var holdCounter: Int = 0

    mutating func configure(sampleRate: Float, lookaheadMS: Float, threshold: Float, enabled: Bool)
    {
        self.enabled = enabled
        self.threshold = clampf(threshold, 0.5, 0.999)

        let sr = max(8_000.0, sampleRate)
        let laMS = clampf(lookaheadMS, 0.0, 20.0)
        let requestedSamples = max(0, Int((sr * laMS * 0.001).rounded()))
        if requestedSamples != lookaheadSamples {
            lookaheadSamples = requestedSamples
            delayLine = lookaheadSamples > 0 ? Array(repeating: 0.0, count: lookaheadSamples) : []
            writeIndex = 0
        }

        let attackS = 0.00035 as Float
        let releaseS = 0.095 as Float
        attackCoeff = expf(-1.0 / (attackS * sr))
        releaseCoeff = expf(-1.0 / (releaseS * sr))
        holdSamples = max(1, Int((0.004 * sr).rounded()))
        holdCounter = 0
        if !enabled {
            gain = 1.0
        }
    }

    mutating func process(_ x: Float) -> Float {
        guard enabled else { return x }

        let detector = fabsf(x)
        var delayed = x
        if lookaheadSamples > 0, !delayLine.isEmpty {
            delayed = delayLine[writeIndex]
            delayLine[writeIndex] = x
            writeIndex += 1
            if writeIndex >= lookaheadSamples {
                writeIndex = 0
            }
        }

        var targetGain: Float = 1.0
        if detector > threshold {
            targetGain = threshold / max(1e-9, detector)
        }
        targetGain = clampf(targetGain, 0.0, 1.0)

        if targetGain < gain {
            gain = (attackCoeff * gain) + ((1.0 - attackCoeff) * targetGain)
            holdCounter = holdSamples
        } else if holdCounter > 0 {
            holdCounter -= 1
        } else {
            gain = (releaseCoeff * gain) + ((1.0 - releaseCoeff) * targetGain)
        }
        return delayed * gain
    }

    var gainReductionDB: Float {
        let safeGain = max(1e-6, gain)
        return max(0.0, -20.0 * log10f(safeGain))
    }
}

private struct RDSGroupSpec {
    let type: Int
    let versionB: Bool
}

private struct RTPlusTag {
    let contentType: Int
    let start: Int
    let length: Int
}

private struct TimedTextFrame {
    let duration: Double
    let text: String
}

private final class BasicRDSCoder {
    private static let bitrate = Float(1187.5)
    private static let crcPoly = 0x5B9
    private static let offsetA = 0x0FC
    private static let offsetB = 0x198
    private static let offsetC = 0x168
    private static let offsetCp = 0x1E0
    private static let offsetD = 0x1B4
    private static let gregorianCalendar = Calendar(identifier: .gregorian)

    private let enabled: Bool
    private let levelScale: Float
    private let piCode: Int
    private let pty: Int
    private let tpFlag: Bool
    private let taFlag: Bool
    private let msFlag: Bool
    private let diStereoFlag: Bool
    private let diHeadFlag: Bool
    private let diCompFlag: Bool
    private let diDynFlag: Bool
    private let afEnabled: Bool
    private let afMethod: String
    private let afCodes: [Int]
    private let psCentered: Bool
    private let rtManualBuffers: Bool
    private let rtCycleAB: Bool
    private let rtRawText: String
    private let rtRawBufferA: String
    private let rtRawBufferB: String
    private let rtBufferA: String
    private let rtBufferB: String
    private let rtCR: Bool
    private let rtCentered: Bool
    private let rtMode2B: Bool
    private let rtCycle: Bool
    private let rtCycleTime: Double
    private let rtActiveBuffer: Int
    private let rtABCycleCount: Int
    private let rdsFreqHz: Float
    private let gaussianEnabled: Bool
    private let gaussianBWHZ: Float
    private let gaussianTaps: Int
    private let schedule: [RDSGroupSpec]
    private let schedulerAuto: Bool
    private let schedulerStandard: Bool
    private let schedulerStandardLPS: Bool
    private let psFrames: [String]
    private let psFrameBytes: [[UInt8]]
    private let rtFrames: [String]
    private let psSequence: [TimedTextFrame]
    private let rtSequence: [TimedTextFrame]
    private let ptynEnabled: Bool
    private let ptynCentered: Bool
    private let ptynFrames: [String]
    private let ptynFrameBytes: [[UInt8]]
    private let ptynSequence: [TimedTextFrame]
    private let lpsEnabled: Bool
    private let lpsCentered: Bool
    private let lpsCR: Bool
    private let lpsFrames: [String]
    private let lpsPreparedFrameBytes: [[UInt8]]
    private let lpsSequence: [TimedTextFrame]
    private let rtPlusEnabled: Bool
    private let rtPlusFormatA: String
    private let rtPlusFormatB: String
    private let nowPlayingEnabled: Bool
    private let nowPlayingState: NowPlayingState?
    private let enCT: Bool
    private let enID: Bool
    private let eccCode: Int
    private let licCode: Int
    private let tzOffset: Double

    private var sampleRate: Float
    private var carrierPhase: Float = 0.0
    private var carrierStep: Float = 0.0
    private var pilotPhaseForRDS: Float = 0.0
    private var pilotStepForRDS: Float = 0.0
    private var bitPhase: Float = 0.0
    private var differentialBit: Int = 0
    private var bitBuffer: [UInt8] = []
    private var bitBufferIndex: Int = 0

    private var scheduleIndex: Int = 0
    private var scheduleGenerateCounter: Int = 0
    private var afPointer: Int = 0
    private var ctMinuteLock: Int = -1
    private var psSegment: Int = 0
    private var psFrameIndex: Int = 0
    private var psSeqIndex: Int = 0
    private var psSeqStart: Double = 0.0
    private var rtSegment: Int = 0
    private var rtFrameIndex: Int = 0
    private var rtSeqIndex: Int = 0
    private var rtSeqStart: Double = 0.0
    private var rtABFlag: Int = 0
    private var rtABCycles: Int = 0
    private var lastManualRTBuffer: Int = 0
    private var rtManualPreparedA: String
    private var rtManualPreparedABytes: [UInt8]
    private var rtManualPreparedB: String
    private var rtManualPreparedBBytes: [UInt8]
    private var ptynSegment: Int = 0
    private var ptynFrameIndex: Int = 0
    private var ptynSeqIndex: Int = 0
    private var ptynSeqStart: Double = 0.0
    private var lpsSegment: Int = 0
    private var lpsFrameIndex: Int = 0
    private var lpsSeqIndex: Int = 0
    private var lpsSeqStart: Double = 0.0
    private var rtPlusToggle: Int = 0
    private var rtPlusTags: [RTPlusTag] = []
    private var rtPlusSignature: String = ""
    private var rtDynamicSignature: String = ""

    private var biphaseKernel: [Float] = []
    private var gaussianKernel: [Float] = []
    private var shapingKernel: [Float] = []
    private var biphaseOverlapAdd: [Float] = []
    private var biphaseOverlapIndex: Int = 0
    private var shapingPeak: Float = 1.0

    init(config: AppConfig, sampleRate: Float, nowPlayingState: NowPlayingState? = nil) {
        self.enabled = config.enRDS && (config.rdsLevel > 0.0)
        self.levelScale = clampf(Float(config.rdsLevel) / 75.0, 0.0, 0.25)
        self.piCode = Self.parseHexWord(config.rdsPI)
        self.pty = max(0, min(31, config.rdsPTY))
        self.tpFlag = config.rdsTP
        self.taFlag = config.rdsTA
        self.msFlag = config.rdsMS
        self.diStereoFlag = config.rdsDI_STEREO
        self.diHeadFlag = config.rdsDI_HEAD
        self.diCompFlag = config.rdsDI_COMP
        self.diDynFlag = config.rdsDI_DYN
        self.afEnabled = config.rdsEnableAF
        self.afMethod = config.rdsAFMethod.uppercased()
        self.afCodes = Self.parseAFList(config.rdsAFList)
        self.psCentered = config.rdsPSCentered
        self.rtManualBuffers = config.rdsRTManualBuffers
        self.rtCycleAB = config.rdsRTCycleAB
        self.rtRawText = config.rdsRTText
        self.rtRawBufferA = config.rdsRTA
        self.rtRawBufferB = config.rdsRTB
        self.rtBufferA = Self.sanitizeText(config.rdsRTA, uppercase: false)
        self.rtBufferB = Self.sanitizeText(config.rdsRTB, uppercase: false)
        self.rtCR = config.rdsRTCR
        self.rtCentered = config.rdsRTCentered
        self.rtMode2B = config.rdsRTMode.uppercased() == "2B"
        self.rtCycle = config.rdsRTCycle
        self.rtCycleTime = max(1.0, config.rdsRTCycleTime)
        self.rtActiveBuffer = max(0, min(1, config.rdsRTActiveBuffer))
        self.rtABCycleCount = max(1, config.rdsRTABCycleCount)
        self.rdsFreqHz = clampf(Float(config.rdsFreq), 1000.0, 120_000.0)
        self.gaussianEnabled = config.rdsGaussianEnabled
        self.gaussianBWHZ = clampf(Float(config.rdsGaussianBWHZ), 600.0, 6000.0)
        self.gaussianTaps = max(9, config.rdsGaussianTaps | 1)
        self.schedule = Self.parseGroupSequence(config.rdsGroupSequence)
        self.schedulerAuto = config.rdsSchedulerAuto
        self.schedulerStandard = config.rdsSchedulerStandard
        self.schedulerStandardLPS = config.rdsSchedulerStandardLPS
        self.psFrames = Self.parseTimedFrames(
            config.rdsPSDynamic, width: 8, uppercase: true, center: psCentered)
        self.psFrameBytes = psFrames.map(Self.rdsBytes)
        self.rtFrames = Self.parseTimedFrames(
            config.rdsRTText,
            width: rtMode2B ? 32 : 64,
            uppercase: false,
            center: rtCentered
        )
        self.psSequence = Self.parseTimedSequence(
            config.rdsPSDynamic, width: 8, uppercase: true, center: psCentered)
        self.rtSequence = Self.parseTimedSequence(
            config.rdsRTText,
            width: rtMode2B ? 32 : 64,
            uppercase: false,
            center: rtCentered
        )
        self.ptynEnabled = config.rdsEnablePTYN
        self.ptynCentered = config.rdsPTYNCentered
        self.ptynFrames = Self.parseTimedFrames(
            config.rdsPTYN, width: 8, uppercase: true, center: ptynCentered)
        self.ptynFrameBytes = ptynFrames.map(Self.rdsBytes)
        self.ptynSequence = Self.parseTimedSequence(
            config.rdsPTYN, width: 8, uppercase: true, center: ptynCentered)
        self.lpsEnabled = config.rdsEnableLPS
        self.lpsCentered = config.rdsLPSCentered
        self.lpsCR = config.rdsLPSCR
        self.lpsFrames = Self.parseTimedFrames(
            config.rdsLongPS32, width: 32, uppercase: false, center: lpsCentered)
        self.lpsPreparedFrameBytes = lpsFrames.map {
            Self.rdsBytes(config.rdsLPSCR ? Self.prepareCRFrame($0, width: 32) : $0)
        }
        self.lpsSequence = Self.parseTimedSequence(
            config.rdsLongPS32, width: 32, uppercase: false, center: lpsCentered)
        self.rtPlusEnabled = config.rdsEnableRTPlus
        self.rtPlusFormatA = config.rdsRTPlusFormatA
        self.rtPlusFormatB = config.rdsRTPlusFormatB
        self.nowPlayingEnabled = config.rdsNowPlayingEnabled
        self.nowPlayingState = nowPlayingState
        self.enCT = config.rdsEnableCT
        self.enID = config.rdsEnableID
        self.eccCode = Self.parseHexByte(config.rdsECC)
        self.licCode = Self.parseHexByte(config.rdsLIC)
        self.tzOffset = config.rdsTZOffset
        self.rtManualPreparedA = ""
        self.rtManualPreparedABytes = []
        self.rtManualPreparedB = ""
        self.rtManualPreparedBBytes = []
        let preparedA = Self.prepareRTFrame(rtBufferA, width: rtMode2B ? 32 : 64, centered: rtCentered, appendCR: rtCR)
        self.rtManualPreparedA = preparedA
        self.rtManualPreparedABytes = Self.rdsBytes(preparedA)
        let preparedB = Self.prepareRTFrame(rtBufferB, width: rtMode2B ? 32 : 64, centered: rtCentered, appendCR: rtCR)
        self.rtManualPreparedB = preparedB
        self.rtManualPreparedBBytes = Self.rdsBytes(preparedB)
        self.sampleRate = max(8_000.0, sampleRate)
        let now = Date().timeIntervalSinceReferenceDate
        self.psSeqStart = now
        self.rtSeqStart = now
        self.ptynSeqStart = now
        self.lpsSeqStart = now
        updateDerivedRates()
        updateShapingFilters()
    }

    func setSampleRate(_ newSampleRate: Float) {
        sampleRate = max(8_000.0, newSampleRate)
        updateDerivedRates()
        updateShapingFilters()
    }

    func nextSample() -> Float {
        guard enabled else { return 0.0 }

        let previousPhase = bitPhase
        var impulse: Float = 0.0
        bitPhase += Self.bitrate / sampleRate
        while bitPhase >= 1.0 {
            bitPhase -= 1.0
            let nextBit = dequeueBit()
            differentialBit ^= Int(nextBit)
            impulse += differentialBit == 0 ? -1.0 : 1.0
        }
        if previousPhase < 0.5, bitPhase >= 0.5 {
            impulse += differentialBit == 0 ? 1.0 : -1.0
        }

        let shaped = nextShapingSample(impulse: impulse)

        let carrier = sinf(carrierPhase)
        carrierPhase += carrierStep
        if carrierPhase >= twoPi {
            carrierPhase -= twoPi
        }
        let normalized = shaped / max(1e-6, shapingPeak)
        return normalized * carrier * levelScale
    }

    func nextSampleWithPilotLock() -> Float {
        guard enabled else { return 0.0 }

        // Phase is now set externally via updateRDSPilotPhase()
        // RDS subcarrier is 3x pilot frequency (57kHz = 3 * 19kHz)
        let rdsPhase = fmodf(3.0 * pilotPhaseForRDS, twoPi)

        let previousPhase = bitPhase
        var impulse: Float = 0.0
        bitPhase += Self.bitrate / sampleRate
        while bitPhase >= 1.0 {
            bitPhase -= 1.0
            let nextBit = dequeueBit()
            differentialBit ^= Int(nextBit)
            impulse += differentialBit == 0 ? -1.0 : 1.0
        }
        if previousPhase < 0.5, bitPhase >= 0.5 {
            impulse += differentialBit == 0 ? 1.0 : -1.0
        }

        let shaped = nextShapingSample(impulse: impulse)

        let carrier = sinf(rdsPhase)
        let normalized = shaped / max(1e-6, shapingPeak)
        return normalized * carrier * levelScale
    }

    private func updateDerivedRates() {
        carrierStep = twoPi * rdsFreqHz / sampleRate
        pilotStepForRDS = twoPi * 19_000.0 / sampleRate
    }

    func updateRDSPilotPhase(_ phase: Float) {
        pilotPhaseForRDS = phase
    }

    private func updateShapingFilters() {
        biphaseKernel = Self.biphaseShapingTaps(
            sampleRate: sampleRate, bitrate: Self.bitrate, tapCount: 301)
        if gaussianEnabled {
            gaussianKernel = Self.gaussianTaps(
                sampleRate: sampleRate, bandwidthHz: gaussianBWHZ, tapCount: gaussianTaps)
        } else {
            gaussianKernel = [1.0]
        }

        shapingKernel = Self.convolveKernels(biphaseKernel, gaussianKernel)
        if shapingKernel.isEmpty {
            shapingKernel = [1.0]
        }
        let olaSize = max(4096, shapingKernel.count * 8)
        biphaseOverlapAdd = Array(repeating: 0.0, count: olaSize)
        biphaseOverlapIndex = 0
        shapingPeak = estimateShapingPeak()
    }

    private func estimateShapingPeak() -> Float {
        let frames = 8192
        var peak: Float = 1e-6
        var testPhase: Float = 0.0
        var testBit: Int = 0
        var localOLA = Array(repeating: Float.zero, count: max(1024, shapingKernel.count * 6))
        var localIndex = 0
        for _ in 0..<frames {
            let previousPhase = testPhase
            var impulse: Float = 0.0
            testPhase += Self.bitrate / sampleRate
            while testPhase >= 1.0 {
                testPhase -= 1.0
                testBit ^= 1
                impulse += testBit == 0 ? -1.0 : 1.0
            }
            if previousPhase < 0.5, testPhase >= 0.5 {
                impulse += testBit == 0 ? 1.0 : -1.0
            }
            let shaped = Self.nextShapingSampleLocal(
                impulse: impulse,
                kernel: shapingKernel,
                overlapAdd: &localOLA,
                index: &localIndex
            )
            let a = fabsf(shaped)
            if a > peak {
                peak = a
            }
        }
        return max(peak, 1e-6)
    }

    private func nextShapingSample(impulse: Float) -> Float {
        Self.nextShapingSampleLocal(
            impulse: impulse,
            kernel: shapingKernel,
            overlapAdd: &biphaseOverlapAdd,
            index: &biphaseOverlapIndex
        )
    }

    private static func nextShapingSampleLocal(
        impulse: Float,
        kernel: [Float],
        overlapAdd: inout [Float],
        index: inout Int
    ) -> Float {
        guard !overlapAdd.isEmpty else { return 0.0 }
        let n = overlapAdd.count
        var idx = index
        let y = overlapAdd[idx]
        overlapAdd[idx] = 0.0

        if impulse != 0.0, !kernel.isEmpty {
            let scaledImpulse = impulse
            var tap = 0
            var pos = idx
            while tap < kernel.count, pos < n {
                overlapAdd[pos] += scaledImpulse * kernel[tap]
                tap += 1
                pos += 1
            }
            pos = 0
            while tap < kernel.count {
                overlapAdd[pos] += scaledImpulse * kernel[tap]
                tap += 1
                pos += 1
            }
        }

        idx += 1
        if idx >= n {
            idx = 0
        }
        index = idx
        return y
    }

    private static func biphaseShapingTaps(sampleRate: Float, bitrate: Float, tapCount: Int)
        -> [Float]
    {
        // Match Python path intent: firwin2-shaped EN50067 biphase impulse response.
        let count = max(9, tapCount | 1)
        let sr = max(8_000.0, sampleRate)
        let nyquist = sr * 0.5
        let td = 1.0 / max(1.0, bitrate)
        let fmax = max(1.0, min(nyquist, 2.0 * bitrate))
        let points = 128

        var freqs = Array(repeating: Float.zero, count: points + 1)
        var gains = Array(repeating: Float.zero, count: points + 1)
        for i in 0..<points {
            let ratio = Float(i) / Float(max(1, points - 1))
            let f = ratio * fmax
            freqs[i] = f
            gains[i] = cosf(Float.pi * f * td * 0.25)
        }
        freqs[points] = nyquist
        gains[points] = 0.0

        let mid = count / 2
        var taps = Array(repeating: Float.zero, count: count)
        for n in 0..<count {
            let m = Float(n - mid)
            var integral: Float = 0.0
            for k in 0..<points {
                let f0 = freqs[k]
                let f1 = freqs[k + 1]
                let g0 = gains[k]
                let g1 = gains[k + 1]
                let c0 = cosf(twoPi * f0 * m / sr)
                let c1 = cosf(twoPi * f1 * m / sr)
                integral += 0.5 * ((g0 * c0) + (g1 * c1)) * (f1 - f0)
            }
            var h = (2.0 / sr) * integral
            let window = 0.54 - (0.46 * cosf(twoPi * Float(n) / Float(max(1, count - 1))))
            h *= window
            taps[n] = h
        }

        var energy: Float = 0.0
        for t in taps {
            energy += t * t
        }
        if energy > 1e-12 {
            let inv = 1.0 / sqrtf(energy)
            for i in 0..<taps.count {
                taps[i] *= inv
            }
        }
        return taps
    }

    private static func gaussianTaps(sampleRate: Float, bandwidthHz: Float, tapCount: Int)
        -> [Float]
    {
        let count = max(9, tapCount | 1)
        let sr = max(8_000.0, sampleRate)
        let bw = max(100.0, bandwidthHz)
        let sigma = sr / (twoPi * bw)
        let half = count / 2
        var taps = Array(repeating: Float.zero, count: count)
        var sum: Float = 0.0
        for i in 0..<count {
            let x = Float(i - half)
            let v = expf(-0.5 * (x / max(1e-6, sigma)) * (x / max(1e-6, sigma)))
            taps[i] = v
            sum += v
        }
        if sum > 0 {
            for i in 0..<count {
                taps[i] /= sum
            }
        }
        return taps
    }

    private static func convolveKernels(_ a: [Float], _ b: [Float]) -> [Float] {
        guard !a.isEmpty, !b.isEmpty else { return [] }
        var out = Array(repeating: Float.zero, count: a.count + b.count - 1)
        for i in 0..<a.count {
            let ai = a[i]
            if ai == 0 { continue }
            for j in 0..<b.count {
                out[i + j] += ai * b[j]
            }
        }
        return out
    }

    private func dequeueBit() -> UInt8 {
        if bitBufferIndex >= bitBuffer.count {
            bitBuffer = nextGroupBits()
            bitBufferIndex = 0
        }
        let bit = bitBuffer[bitBufferIndex]
        bitBufferIndex += 1
        return bit
    }

    private func nextGroupBits() -> [UInt8] {
        if let ctBits = buildClockTimeGroupIfNeeded() {
            return ctBits
        }

        let activeSchedule: [RDSGroupSpec]
        if schedulerStandard {
            activeSchedule = generateStandardSchedule()
        } else if schedulerAuto {
            activeSchedule = generateAutoSchedule()
        } else {
            activeSchedule = schedule
        }
        if activeSchedule.isEmpty {
            return buildGroup0(versionB: false)
        }

        let entry = activeSchedule[scheduleIndex % activeSchedule.count]
        scheduleIndex += 1
        switch entry.type {
        case 2:
            return buildGroup2(versionB: entry.versionB)
        case 3:
            return rtPlusEnabled ? buildGroup3A() : buildGroup0(versionB: false)
        case 4:
            return enCT
                ? (buildClockTimeGroupImmediate() ?? buildGroup0(versionB: false))
                : buildGroup0(versionB: false)
        case 10:
            return ptynEnabled ? buildGroup10A() : buildGroup0(versionB: false)
        case 11:
            return rtPlusEnabled ? buildGroup11A() : buildGroup0(versionB: false)
        case 15:
            return lpsEnabled ? buildGroup15A() : buildGroup0(versionB: false)
        case 1:
            return enID ? buildGroup1A() : buildGroup0(versionB: false)
        default:
            return buildGroup0(versionB: entry.versionB)
        }
    }

    private func buildGroup0(versionB: Bool) -> [UInt8] {
        updatePSSequenceIfNeeded()
        let bytes = psSequence.isEmpty ? psFrameBytes[psFrameIndex] : Self.rdsBytes(psSequence[psSeqIndex].text)
        let segment = psSegment % 4
        psSegment += 1
        let diBit = diBitForSegment(segment) ? 0x04 : 0x00
        let b2Tail = (taFlag ? 0x10 : 0) | (msFlag ? 0x08 : 0) | diBit | segment
        let b3Value: Int
        if versionB {
            b3Value = piCode
        } else if afEnabled, afMethod == "A", !afCodes.isEmpty {
            b3Value = nextAFBlockValue()
        } else {
            b3Value = 0xE0E0
        }
        let idx = segment * 2
        let b4Value = (Int(bytes[idx]) << 8) | Int(bytes[idx + 1])
        return buildGroupBits(
            groupType: 0,
            versionB: versionB,
            b2Tail: b2Tail,
            b3Value: b3Value,
            b4Value: b4Value
        )
    }

    private func buildGroup2(versionB: Bool) -> [UInt8] {
        let useVersionB = rtMode2B || versionB
        let limit = useVersionB ? 32 : 64
        let frameData = currentRTFrame(limit: limit)
        let frame = frameData.text
        let bytes = frameData.bytes
        let segment = rtSegment % 16
        rtSegment += 1
        let abFlag: Int
        if rtManualBuffers {
            abFlag = currentManualRTBuffer()
        } else {
            abFlag = rtABFlag & 1
        }
        let b2Tail = ((abFlag & 1) << 4) | segment
        if rtPlusEnabled {
            let snapshot = currentNowPlayingSnapshot()
            let selectedFormat =
                (nowPlayingEnabled && snapshot.hasContent)
                ? ""
                : ((abFlag == 0) ? rtPlusFormatA : rtPlusFormatB)
            refreshRTPlusTagsIfNeeded(
                text: frame,
                format: selectedFormat,
                snapshot: snapshot
            )
        }
        if useVersionB {
            let idx = segment * 2
            let b4Value = (Int(bytes[idx]) << 8) | Int(bytes[idx + 1])
            return buildGroupBits(
                groupType: 2,
                versionB: true,
                b2Tail: b2Tail,
                b3Value: piCode,
                b4Value: b4Value
            )
        }
        let idx = segment * 4
        let b3Value = (Int(bytes[idx]) << 8) | Int(bytes[idx + 1])
        let b4Value = (Int(bytes[idx + 2]) << 8) | Int(bytes[idx + 3])
        return buildGroupBits(
            groupType: 2,
            versionB: false,
            b2Tail: b2Tail,
            b3Value: b3Value,
            b4Value: b4Value
        )
    }

    private func buildGroup3A() -> [UInt8] {
        // ODA application identification for RT+ (AID 0x4BD7)
        return buildGroupBits(
            groupType: 3,
            versionB: false,
            b2Tail: 22,
            b3Value: 0x0000,
            b4Value: 0x4BD7
        )
    }

    private func buildGroup10A() -> [UInt8] {
        updatePTYNSequenceIfNeeded()
        let bytes =
            ptynSequence.isEmpty ? ptynFrameBytes[ptynFrameIndex] : Self.rdsBytes(ptynSequence[ptynSeqIndex].text)
        let segment = ptynSegment % 2
        ptynSegment += 1
        let idx = segment * 4
        let b3Value = (Int(bytes[idx]) << 8) | Int(bytes[idx + 1])
        let b4Value = (Int(bytes[idx + 2]) << 8) | Int(bytes[idx + 3])
        return buildGroupBits(
            groupType: 10,
            versionB: false,
            b2Tail: segment,
            b3Value: b3Value,
            b4Value: b4Value
        )
    }

    private func buildGroup11A() -> [UInt8] {
        var t1Type = 0
        var t1Start = 0
        var t1Length = 0
        var t2Type = 0
        var t2Start = 0
        var t2Length = 0

        let orderedTags = Array(rtPlusTags.prefix(2))
        if orderedTags.count > 0 {
            t1Type = orderedTags[0].contentType
            t1Start = max(0, min(63, orderedTags[0].start))
            t1Length = max(0, min(63, orderedTags[0].length > 0 ? orderedTags[0].length - 1 : 0))
        }
        if orderedTags.count > 1 {
            t2Type = orderedTags[1].contentType
            t2Start = max(0, min(63, orderedTags[1].start))
            t2Length = max(0, min(31, orderedTags[1].length > 0 ? orderedTags[1].length - 1 : 0))
        }

        let b2Tail = ((rtPlusToggle & 1) << 4) | 0x08 | ((t1Type >> 3) & 0x07)
        let b3Value =
            ((t1Type & 0x07) << 13)
            | ((t1Start & 0x3F) << 7)
            | ((t1Length & 0x3F) << 1)
            | ((t2Type >> 5) & 0x01)
        let b4Value =
            ((t2Type & 0x1F) << 11)
            | ((t2Start & 0x3F) << 5)
            | (t2Length & 0x1F)
        return buildGroupBits(
            groupType: 11,
            versionB: false,
            b2Tail: b2Tail,
            b3Value: b3Value,
            b4Value: b4Value
        )
    }

    private func buildGroup15A() -> [UInt8] {
        updateLPSSequenceIfNeeded()
        let bytes: [UInt8]
        if lpsSequence.isEmpty {
            bytes = lpsPreparedFrameBytes[lpsFrameIndex]
        } else {
            let frame = lpsSequence[lpsSeqIndex].text
            let prepared = lpsCR ? Self.prepareCRFrame(frame, width: 32) : frame
            bytes = Self.rdsBytes(prepared)
        }
        let segment = lpsSegment % 8
        lpsSegment += 1
        let idx = segment * 4
        let b3Value = (Int(bytes[idx]) << 8) | Int(bytes[idx + 1])
        let b4Value = (Int(bytes[idx + 2]) << 8) | Int(bytes[idx + 3])
        return buildGroupBits(
            groupType: 15,
            versionB: false,
            b2Tail: segment,
            b3Value: b3Value,
            b4Value: b4Value
        )
    }

    private func buildGroup1A() -> [UInt8] {
        // Alternate ECC/LIC variants similar to Python scheduler behavior.
        let variants = [0, 3]
        let selector = Int(Date().timeIntervalSince1970 / 2.0) % 2
        let variant = variants[selector]
        let idValue = (variant == 0) ? eccCode : licCode
        let b3Value = ((variant & 0x0F) << 12) | (idValue & 0xFF)
        return buildGroupBits(
            groupType: 1,
            versionB: false,
            b2Tail: 0,
            b3Value: b3Value,
            b4Value: 0
        )
    }

    private func buildClockTimeGroupIfNeeded() -> [UInt8]? {
        guard enCT else { return nil }
        let now = Date()
        let comps = Self.gregorianCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: now)
        guard let year = comps.year,
            let month = comps.month,
            let day = comps.day,
            let hour = comps.hour,
            let minute = comps.minute,
            let second = comps.second
        else {
            return nil
        }
        guard second == 0 else { return nil }
        guard minute != ctMinuteLock else { return nil }
        ctMinuteLock = minute

        return buildClockTimeGroupFromComponents(
            year: year, month: month, day: day, hour: hour, minute: minute)
    }

    private func buildClockTimeGroupImmediate() -> [UInt8]? {
        guard enCT else { return nil }
        let now = Date()
        let comps = Self.gregorianCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        guard let year = comps.year,
            let month = comps.month,
            let day = comps.day,
            let hour = comps.hour,
            let minute = comps.minute
        else {
            return nil
        }
        return buildClockTimeGroupFromComponents(
            year: year, month: month, day: day, hour: hour, minute: minute)
    }

    private func buildClockTimeGroupFromComponents(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int
    ) -> [UInt8] {
        let mjd = Self.modifiedJulianDay(year: year, month: month, day: day)
        let tzHalfHours = max(0, min(31, Int(abs(tzOffset) * 2.0)))
        let tzSign = tzOffset < 0 ? 1 : 0
        let b2Tail = (mjd >> 15) & 0x3
        let b3Value = ((mjd & 0x7FFF) << 1) | ((hour >> 4) & 0x1)
        let b4Value =
            ((hour & 0x0F) << 12) | ((minute & 0x3F) << 6) | (tzSign << 5) | (tzHalfHours & 0x1F)
        return buildGroupBits(
            groupType: 4,
            versionB: false,
            b2Tail: b2Tail,
            b3Value: b3Value,
            b4Value: b4Value
        )
    }

    private func generateAutoSchedule() -> [RDSGroupSpec] {
        var seq: [RDSGroupSpec] = [
            RDSGroupSpec(type: 0, versionB: false),
            RDSGroupSpec(type: 0, versionB: false),
            RDSGroupSpec(type: 2, versionB: rtMode2B),
            RDSGroupSpec(type: 0, versionB: false),
            RDSGroupSpec(type: 2, versionB: rtMode2B),
            RDSGroupSpec(type: 0, versionB: false),
            RDSGroupSpec(type: 0, versionB: false),
            RDSGroupSpec(type: 0, versionB: false),
            RDSGroupSpec(type: 2, versionB: rtMode2B),
            RDSGroupSpec(type: 0, versionB: false),
            RDSGroupSpec(type: 2, versionB: rtMode2B),
            RDSGroupSpec(type: 0, versionB: false),
            RDSGroupSpec(type: 2, versionB: rtMode2B),
            RDSGroupSpec(type: 0, versionB: false),
            RDSGroupSpec(type: 2, versionB: rtMode2B),
            RDSGroupSpec(type: 0, versionB: false),
            RDSGroupSpec(type: 2, versionB: rtMode2B),
            RDSGroupSpec(type: 0, versionB: false),
            RDSGroupSpec(type: 2, versionB: rtMode2B),
            RDSGroupSpec(type: 0, versionB: false),
        ]
        if lpsEnabled {
            seq.append(RDSGroupSpec(type: 15, versionB: false))
            seq.append(RDSGroupSpec(type: 15, versionB: false))
        }
        if ptynEnabled {
            seq.append(RDSGroupSpec(type: 10, versionB: false))
            seq.append(RDSGroupSpec(type: 10, versionB: false))
        }
        if enID {
            seq.append(RDSGroupSpec(type: 1, versionB: false))
        }
        if rtPlusEnabled {
            if (scheduleGenerateCounter % 2) == 0 {
                seq.append(RDSGroupSpec(type: 3, versionB: false))
            }
            seq.append(RDSGroupSpec(type: 11, versionB: false))
        }
        scheduleGenerateCounter += 1
        return seq
    }

    private func generateStandardSchedule() -> [RDSGroupSpec] {
        var seq: [RDSGroupSpec] = [
            RDSGroupSpec(type: 0, versionB: false),
            RDSGroupSpec(type: 0, versionB: false),
            RDSGroupSpec(type: 0, versionB: false),
            RDSGroupSpec(type: 2, versionB: rtMode2B),
            RDSGroupSpec(type: 0, versionB: false),
            RDSGroupSpec(type: 2, versionB: rtMode2B),
            RDSGroupSpec(type: 0, versionB: false),
            RDSGroupSpec(type: 0, versionB: false),
            RDSGroupSpec(type: 0, versionB: false),
            RDSGroupSpec(type: 2, versionB: rtMode2B),
            RDSGroupSpec(type: 0, versionB: false),
            RDSGroupSpec(type: 2, versionB: rtMode2B),
            RDSGroupSpec(type: 0, versionB: false),
            RDSGroupSpec(type: 0, versionB: false),
        ]
        if enID {
            seq.append(RDSGroupSpec(type: 1, versionB: false))
        }
        if ptynEnabled {
            seq.append(RDSGroupSpec(type: 10, versionB: false))
        }
        if rtPlusEnabled {
            seq.append(RDSGroupSpec(type: 3, versionB: false))
            seq.append(RDSGroupSpec(type: 11, versionB: false))
        }
        if schedulerStandardLPS && lpsEnabled {
            seq.append(RDSGroupSpec(type: 15, versionB: false))
        }
        return seq
    }

    private func diBitForSegment(_ segment: Int) -> Bool {
        switch segment % 4 {
        case 0: return diDynFlag
        case 1: return diCompFlag
        case 2: return diHeadFlag
        default: return diStereoFlag
        }
    }

    private func nextAFBlockValue() -> Int {
        guard !afCodes.isEmpty else { return 0xE0E0 }
        if afPointer == 0 {
            afPointer = 1
            let countCode = (224 + min(25, afCodes.count)) & 0xFF
            return (countCode << 8) | (afCodes[0] & 0xFF)
        }
        let f1 = afCodes[min(afPointer, afCodes.count - 1)] & 0xFF
        let f2: Int
        if afPointer + 1 < afCodes.count {
            f2 = afCodes[afPointer + 1] & 0xFF
            afPointer += 2
            if afPointer >= afCodes.count {
                afPointer = 0
            }
        } else {
            f2 = 205
            afPointer = 0
        }
        return (f1 << 8) | f2
    }

    private func updatePSSequenceIfNeeded() {
        guard !psSequence.isEmpty else { return }
        let now = Date().timeIntervalSinceReferenceDate
        let current = psSequence[min(psSeqIndex, psSequence.count - 1)]
        if now - psSeqStart >= current.duration {
            psSeqIndex = (psSeqIndex + 1) % psSequence.count
            psSeqStart = now
            psSegment = 0
        }
    }

    private func updatePTYNSequenceIfNeeded() {
        guard !ptynSequence.isEmpty else { return }
        let now = Date().timeIntervalSinceReferenceDate
        let current = ptynSequence[min(ptynSeqIndex, ptynSequence.count - 1)]
        if now - ptynSeqStart >= current.duration {
            ptynSeqIndex = (ptynSeqIndex + 1) % ptynSequence.count
            ptynSeqStart = now
            ptynSegment = 0
        }
    }

    private func updateLPSSequenceIfNeeded() {
        guard !lpsSequence.isEmpty else { return }
        let now = Date().timeIntervalSinceReferenceDate
        let current = lpsSequence[min(lpsSeqIndex, lpsSequence.count - 1)]
        if now - lpsSeqStart >= current.duration {
            lpsSeqIndex = (lpsSeqIndex + 1) % lpsSequence.count
            lpsSeqStart = now
            lpsSegment = 0
        }
    }

    private func currentManualRTBuffer() -> Int {
        if rtCycle {
            let elapsed = Date().timeIntervalSinceReferenceDate - rtSeqStart
            return Int(elapsed / max(1.0, rtCycleTime)) % 2
        }
        return rtActiveBuffer
    }

    private func currentRTFrame(limit: Int) -> (text: String, bytes: [UInt8]) {
        let nowPlayingSnapshot = currentNowPlayingSnapshot()
        if rtManualBuffers {
            let buf = currentManualRTBuffer()
            if buf != lastManualRTBuffer {
                rtSegment = 0
                lastManualRTBuffer = buf
            }
            if nowPlayingEnabled {
                let template = (buf == 0) ? rtRawBufferA : rtRawBufferB
                let prepared = Self.prepareRTFrame(
                    Self.expandNowPlayingMacros(template, snapshot: nowPlayingSnapshot),
                    width: limit,
                    centered: rtCentered,
                    appendCR: rtCR
                )
                return (prepared, Self.rdsBytes(prepared))
            }
            if buf == 0 {
                return (rtManualPreparedA, rtManualPreparedABytes)
            }
            return (rtManualPreparedB, rtManualPreparedBBytes)
        }

        if nowPlayingEnabled {
            let resolvedRaw = Self.expandNowPlayingMacros(rtRawText, snapshot: nowPlayingSnapshot)
            let signature = "\(resolvedRaw)|\(nowPlayingSnapshot.revision)"
            if signature != rtDynamicSignature {
                rtDynamicSignature = signature
                rtSegment = 0
                if !rtCycleAB {
                    rtABFlag ^= 1
                }
            }
            let dynamicSequence = Self.parseTimedSequence(
                resolvedRaw,
                width: limit,
                uppercase: false,
                center: rtCentered
            )
            guard !dynamicSequence.isEmpty else {
                let frame = Self.prepareRTFrame("", width: limit, centered: rtCentered, appendCR: rtCR)
                return (frame, Self.rdsBytes(frame))
            }

            let now = Date().timeIntervalSinceReferenceDate
            let current = dynamicSequence[min(rtSeqIndex, dynamicSequence.count - 1)]
            if now - rtSeqStart >= current.duration {
                let prev = rtSeqIndex
                rtSeqIndex = (rtSeqIndex + 1) % dynamicSequence.count
                rtSeqStart = now
                rtSegment = 0
                if !rtCycleAB && rtSeqIndex != prev {
                    rtABFlag ^= 1
                }
            }

            if rtCycleAB, rtSegment > 0, (rtSegment % 16) == 0 {
                rtABCycles += 1
                if rtABCycles >= rtABCycleCount {
                    rtABFlag ^= 1
                    rtABCycles = 0
                }
            }

            let frame = dynamicSequence[min(rtSeqIndex, dynamicSequence.count - 1)].text
            let prepared = Self.prepareRTFrame(frame, width: limit, centered: rtCentered, appendCR: rtCR)
            return (prepared, Self.rdsBytes(prepared))
        }

        guard !rtSequence.isEmpty else {
            let frame = Self.prepareRTFrame(
                rtFrames[rtFrameIndex], width: limit, centered: rtCentered, appendCR: rtCR)
            return (frame, Self.rdsBytes(frame))
        }

        let now = Date().timeIntervalSinceReferenceDate
        let current = rtSequence[min(rtSeqIndex, rtSequence.count - 1)]
        if now - rtSeqStart >= current.duration {
            let prev = rtSeqIndex
            rtSeqIndex = (rtSeqIndex + 1) % rtSequence.count
            rtSeqStart = now
            rtSegment = 0
            if !rtCycleAB && rtSeqIndex != prev {
                rtABFlag ^= 1
            }
        }

        if rtCycleAB, rtSegment > 0, (rtSegment % 16) == 0 {
            rtABCycles += 1
            if rtABCycles >= rtABCycleCount {
                rtABFlag ^= 1
                rtABCycles = 0
            }
        }

        let frame = rtSequence[min(rtSeqIndex, rtSequence.count - 1)].text
        let prepared = Self.prepareRTFrame(frame, width: limit, centered: rtCentered, appendCR: rtCR)
        return (prepared, Self.rdsBytes(prepared))
    }

    private func currentNowPlayingSnapshot() -> NowPlayingSnapshot {
        guard nowPlayingEnabled, let nowPlayingState else { return .empty }
        return nowPlayingState.currentSnapshot()
    }

    private static func rdsBytes(_ text: String) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0D, 0x20...0x7E:
                out.append(UInt8(scalar.value))
            default:
                if let mapped = rdsDirectByteMap[scalar.value] {
                    out.append(mapped)
                } else {
                    out.append(UInt8(ascii: "?"))
                }
            }
        }
        return out
    }

    private func buildGroupBits(
        groupType: Int,
        versionB: Bool,
        b2Tail: Int,
        b3Value: Int,
        b4Value: Int
    ) -> [UInt8] {
        let b1Data = piCode & 0xFFFF
        let b2Data =
            ((groupType & 0x0F) << 12)
            | ((versionB ? 1 : 0) << 11)
            | ((tpFlag ? 1 : 0) << 10)
            | ((pty & 0x1F) << 5)
            | (b2Tail & 0x1F)
        let b3Offset = versionB ? Self.offsetCp : Self.offsetC
        let block1 = Self.withCheckword(word: b1Data, offset: Self.offsetA)
        let block2 = Self.withCheckword(word: b2Data, offset: Self.offsetB)
        let block3 = Self.withCheckword(word: b3Value & 0xFFFF, offset: b3Offset)
        let block4 = Self.withCheckword(word: b4Value & 0xFFFF, offset: Self.offsetD)

        var out: [UInt8] = []
        out.reserveCapacity(104)
        for block in [block1, block2, block3, block4] {
            for shift in stride(from: 25, through: 0, by: -1) {
                out.append(UInt8((block >> shift) & 1))
            }
        }
        return out
    }

    private static func withCheckword(word: Int, offset: Int) -> Int {
        let checkword = crc(word: word, offset: offset)
        return ((word & 0xFFFF) << 10) | (checkword & 0x03FF)
    }

    private static func crc(word: Int, offset: Int) -> Int {
        var reg = (word & 0xFFFF) << 10
        for _ in 0..<16 {
            if ((reg >> 25) & 1) == 1 {
                reg ^= (crcPoly << 15)
            }
            reg = (reg << 1) & 0x03FF_FFFF
        }
        return ((reg >> 16) & 0x03FF) ^ offset
    }

    private static func parseHexWord(_ text: String) -> Int {
        let upper = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleaned = upper.filter { ch in
            switch ch {
            case "0"..."9", "A"..."F":
                return true
            default:
                return false
            }
        }
        if cleaned.isEmpty {
            return 0
        }
        if let parsed = Int(cleaned, radix: 16) {
            return parsed & 0xFFFF
        }
        return 0
    }

    private static func parseGroupSequence(_ raw: String) -> [RDSGroupSpec] {
        let tokens =
            raw
            .uppercased()
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        var out: [RDSGroupSpec] = []
        for token in tokens {
            guard !token.isEmpty else { continue }
            var digits = ""
            var suffix = ""
            for scalar in token.unicodeScalars {
                if scalar.value >= 48, scalar.value <= 57 {
                    digits.append(Character(scalar))
                } else {
                    suffix.append(Character(scalar))
                }
            }
            guard let groupType = Int(digits) else { continue }
            let versionB = (groupType == 0 || groupType == 2) && suffix == "B"
            if groupType == 0 || groupType == 1 || groupType == 2 || groupType == 3
                || groupType == 4
                || groupType == 10 || groupType == 11 || groupType == 15
            {
                out.append(RDSGroupSpec(type: groupType, versionB: versionB))
            }
        }
        if out.isEmpty {
            return [
                RDSGroupSpec(type: 0, versionB: false),
                RDSGroupSpec(type: 0, versionB: false),
                RDSGroupSpec(type: 2, versionB: false),
                RDSGroupSpec(type: 0, versionB: false),
            ]
        }
        return out
    }

    private func refreshRTPlusTagsIfNeeded(
        text: String,
        format: String,
        snapshot: NowPlayingSnapshot
    ) {
        let signature =
            text + "|" + format + "|" + snapshot.display + "|" + snapshot.artist + "|" + snapshot.title
        if signature == rtPlusSignature {
            return
        }
        rtPlusSignature = signature
        rtPlusToggle ^= 1
        rtPlusTags = Self.parseRTPlusTags(text: text, format: format, snapshot: snapshot)
    }

    private static func parseTimedFrames(_ raw: String, width: Int, uppercase: Bool, center: Bool)
        -> [String]
    {
        return parseTimedSequence(raw, width: width, uppercase: uppercase, center: center).map(
            \.text)
    }

    private static func parseTimedSequence(_ raw: String, width: Int, uppercase: Bool, center: Bool)
        -> [TimedTextFrame]
    {
        let resolved = resolveTextMarkers(raw) ?? raw
        let trimmed = resolved.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return [TimedTextFrame(duration: 10.0, text: String(repeating: " ", count: width))]
        }

        var out: [TimedTextFrame] = []
        let startsTimed = trimmed.range(of: #"^\s*\d+s:"#, options: .regularExpression) != nil

        if startsTimed {
            let slashParts =
                trimmed
                .split(separator: "/", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            if slashParts.count > 1 {
                for part in slashParts where !part.isEmpty {
                    if let timed = parseTimedPrefix(part) {
                        let chunks = splitAndPad(
                            timed.text, width: width, uppercase: uppercase, center: center)
                        if chunks.isEmpty {
                            out.append(
                                TimedTextFrame(
                                    duration: timed.duration,
                                    text: String(repeating: " ", count: width)))
                        } else {
                            for chunk in chunks {
                                out.append(TimedTextFrame(duration: timed.duration, text: chunk))
                            }
                        }
                    } else {
                        let chunks = splitAndPad(
                            part, width: width, uppercase: uppercase, center: center)
                        if chunks.isEmpty {
                            out.append(
                                TimedTextFrame(
                                    duration: 2.5, text: String(repeating: " ", count: width)))
                        } else {
                            for chunk in chunks {
                                out.append(TimedTextFrame(duration: 2.5, text: chunk))
                            }
                        }
                    }
                }
            } else if let regex = try? NSRegularExpression(
                pattern: "(\\d+)s:(.*?)(?=(?:\\s+\\d+s:)|$)",
                options: []
            ) {
                let ns = trimmed as NSString
                let matches = regex.matches(
                    in: trimmed, options: [], range: NSRange(location: 0, length: ns.length))
                for m in matches where m.numberOfRanges >= 3 {
                    let durationRaw = ns.substring(with: m.range(at: 1))
                    let duration = max(0.5, Double(durationRaw) ?? 2.5)
                    let segment = ns.substring(with: m.range(at: 2)).trimmingCharacters(
                        in: .whitespacesAndNewlines)
                    let chunks = splitAndPad(
                        segment, width: width, uppercase: uppercase, center: center)
                    if chunks.isEmpty {
                        out.append(
                            TimedTextFrame(
                                duration: duration, text: String(repeating: " ", count: width)))
                    } else {
                        for chunk in chunks {
                            out.append(TimedTextFrame(duration: duration, text: chunk))
                        }
                    }
                }
            }
        } else {
            let base =
                (width <= 8) ? resolved : resolved.trimmingCharacters(in: .whitespacesAndNewlines)
            if base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return [TimedTextFrame(duration: 10.0, text: String(repeating: " ", count: width))]
            }
            let chunks = splitAndPad(base, width: width, uppercase: uppercase, center: center)
            if chunks.count <= 1 {
                let single = chunks.first ?? String(repeating: " ", count: width)
                out.append(TimedTextFrame(duration: 10.0, text: single))
            } else {
                for chunk in chunks {
                    out.append(TimedTextFrame(duration: 2.5, text: chunk))
                }
            }
        }

        if out.isEmpty {
            return [TimedTextFrame(duration: 10.0, text: String(repeating: " ", count: width))]
        }
        return out
    }

    private static func splitAndPad(_ raw: String, width: Int, uppercase: Bool, center: Bool)
        -> [String]
    {
        let normalized = sanitizeText(raw, uppercase: uppercase)
        let words = normalized.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if words.isEmpty {
            return [String(repeating: " ", count: width)]
        }
        var out: [String] = []
        var current = ""

        func pad(_ value: String) -> String {
            let clipped = value.count <= width ? value : String(value.prefix(width))
            if clipped.count >= width {
                return clipped
            }
            let padding = width - clipped.count
            if center {
                let left = padding / 2
                let right = padding - left
                return String(repeating: " ", count: left) + clipped
                    + String(repeating: " ", count: right)
            }
            return clipped + String(repeating: " ", count: padding)
        }

        func chunkWord(_ word: String) -> [String] {
            guard word.count > width else { return [word] }
            let chars = Array(word)
            var chunks: [String] = []
            var idx = 0
            while idx < chars.count {
                let end = min(chars.count, idx + width)
                chunks.append(String(chars[idx..<end]))
                idx = end
            }
            return chunks
        }

        for word in words {
            if word.count > width {
                if !current.isEmpty {
                    out.append(pad(current))
                    current = ""
                }
                let chunks = chunkWord(word)
                if chunks.count > 1 {
                    for chunk in chunks.dropLast() {
                        out.append(pad(chunk))
                    }
                }
                current = chunks.last ?? ""
                continue
            }
            let test = current.isEmpty ? word : "\(current) \(word)"
            if test.count <= width {
                current = test
            } else {
                if !current.isEmpty {
                    out.append(pad(current))
                }
                current = word
            }
        }
        if !current.isEmpty {
            out.append(pad(current))
        }
        if out.isEmpty {
            out.append(String(repeating: " ", count: width))
        }
        return out
    }

    private static let rdsDirectByteMap: [UInt32: UInt8] = [
        0x00D8: 0xE7,
        0x00F8: 0xF7,
    ]

    private static let rdsTransliterationMap: [UInt32: String] = [
        0x00C9: "E", 0x00C8: "E", 0x00CA: "E", 0x00CB: "E",
        0x00E9: "e", 0x00E8: "e", 0x00EA: "e", 0x00EB: "e",
        0x00C1: "A", 0x00C0: "A", 0x00C2: "A", 0x00C4: "A", 0x00C5: "A",
        0x00E1: "a", 0x00E0: "a", 0x00E2: "a", 0x00E4: "a", 0x00E5: "a",
        0x00CD: "I", 0x00CC: "I", 0x00CE: "I", 0x00CF: "I",
        0x00ED: "i", 0x00EC: "i", 0x00EE: "i", 0x00EF: "i",
        0x00D3: "O", 0x00D2: "O", 0x00D4: "O", 0x00D6: "O",
        0x00F3: "o", 0x00F2: "o", 0x00F4: "o", 0x00F6: "o",
        0x00DA: "U", 0x00D9: "U", 0x00DB: "U", 0x00DC: "U",
        0x00FA: "u", 0x00F9: "u", 0x00FB: "u", 0x00FC: "u",
        0x00C7: "C", 0x00E7: "c",
        0x00D1: "N", 0x00F1: "n",
        0x00C6: "AE", 0x00E6: "ae",
        0x0152: "OE", 0x0153: "oe",
        0x00DF: "ss",
        0x20AC: "E",
        0x00B0: " ", 0x2122: " ", 0x00AE: " ",
    ]

    private static func resolveTextMarkers(_ text: String) -> String? {
        guard text.contains("\\") else { return text }
        var failed = false
        var resolved = text
        resolved = replaceMarkers(in: resolved, pattern: #"\\R\"([^\"]+)\""#) { path in
            guard let loaded = loadTextFromFile(path) else {
                failed = true
                return ""
            }
            return cleanMarkerSpaces(transliterateRDSText(loaded)).uppercased()
        }
        resolved = replaceMarkers(in: resolved, pattern: #"\\r\"([^\"]+)\""#) { path in
            guard let loaded = loadTextFromFile(path) else {
                failed = true
                return ""
            }
            return cleanMarkerSpaces(transliterateRDSText(loaded))
        }
        resolved = replaceMarkers(in: resolved, pattern: #"\\w\"([^\"]+)\""#) { source in
            guard let loaded = loadTextFromURL(source) else {
                failed = true
                return ""
            }
            return cleanMarkerSpaces(transliterateRDSText(loaded))
        }
        return failed ? nil : resolved
    }

    private static func replaceMarkers(
        in source: String,
        pattern: String,
        transform: (String) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return source
        }
        let ns = source as NSString
        let matches = regex.matches(
            in: source, options: [], range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty {
            return source
        }
        var out = source
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2 else { continue }
            let wholeRange = match.range(at: 0)
            let capRange = match.range(at: 1)
            let token = ns.substring(with: capRange)
            let replacement = transform(token)
            if let r = Range(wholeRange, in: out) {
                out.replaceSubrange(r, with: replacement)
            }
        }
        return out
    }

    private static func parseTimedPrefix(_ text: String) -> (duration: Double, text: String)? {
        guard let regex = try? NSRegularExpression(pattern: #"^\s*(\d+)s:(.*)$"#, options: [])
        else {
            return nil
        }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
            match.numberOfRanges >= 3
        else {
            return nil
        }
        let duration = max(0.5, Double(ns.substring(with: match.range(at: 1))) ?? 2.5)
        let segment = ns.substring(with: match.range(at: 2))
        return (duration, segment)
    }

    private static func loadTextFromFile(_ path: String) -> String? {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private static func loadTextFromURL(_ source: String) -> String? {
        guard let url = URL(string: source) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0
        let semaphore = DispatchSemaphore(value: 0)
        final class PayloadBox: @unchecked Sendable {
            var value: String?
        }
        let box = PayloadBox()
        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { semaphore.signal() }
            guard let data else { return }
            box.value = String(data: data, encoding: .utf8)
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 2.5)
        task.cancel()
        return box.value
    }

    private static func cleanMarkerSpaces(_ text: String) -> String {
        return text.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(
            of: "\n", with: " ")
    }

    private static func transliterateRDSText(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            if scalar.value == 0x0D || (scalar.value >= 0x20 && scalar.value <= 0x7E) {
                out.append(Character(scalar))
            } else if rdsDirectByteMap[scalar.value] != nil {
                out.append(Character(scalar))
            } else if let mapped = rdsTransliterationMap[scalar.value] {
                out += mapped
            } else {
                let folded = String(scalar).folding(
                    options: [.diacriticInsensitive, .widthInsensitive],
                    locale: .current
                )
                var appended = false
                for foldedScalar in folded.unicodeScalars {
                    if foldedScalar.value == 0x0D
                        || (foldedScalar.value >= 0x20 && foldedScalar.value <= 0x7E)
                    {
                        out.append(Character(foldedScalar))
                        appended = true
                    }
                }
                if !appended {
                    out += "?"
                }
            }
        }
        return out
    }

    private static func sanitizeText(_ raw: String, uppercase: Bool) -> String {
        let transliterated = transliterateRDSText(raw)
        let mapped = transliterated.unicodeScalars.map { scalar -> Character in
            if scalar.value >= 0x20, scalar.value <= 0x7E {
                return Character(scalar)
            }
            return " "
        }
        let base = String(mapped)
        if uppercase {
            return base.uppercased()
        }
        return base
    }

    private static func prepareRTFrame(_ raw: String, width: Int, centered: Bool, appendCR: Bool)
        -> String
    {
        let sanitized = sanitizeText(raw, uppercase: false)
        let limited = String(sanitized.prefix(width))
        if appendCR {
            let trimmed = limited.trimmingCharacters(in: .whitespacesAndNewlines)
            let withCR = trimmed + "\r"
            if withCR.count >= width {
                return String(withCR.prefix(width))
            }
            return withCR + String(repeating: " ", count: width - withCR.count)
        }
        if centered, limited.count < width {
            let total = width - limited.count
            let left = total / 2
            let right = total - left
            return String(repeating: " ", count: left) + limited
                + String(repeating: " ", count: right)
        }
        if limited.count < width {
            return limited + String(repeating: " ", count: width - limited.count)
        }
        return limited
    }

    private static func prepareCRFrame(_ raw: String, width: Int) -> String {
        let sanitized = sanitizeText(raw, uppercase: false)
        let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        let withCR = trimmed + "\r"
        if withCR.count >= width {
            return String(withCR.prefix(width))
        }
        return withCR + String(repeating: " ", count: width - withCR.count)
    }

    private static func parseAFList(_ raw: String) -> [Int] {
        let tokens = raw.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var out: [Int] = []
        for token in tokens {
            guard let mhz = Double(token) else { continue }
            if mhz >= 87.6, mhz <= 107.9 {
                out.append(Int((mhz - 87.5) / 0.1 + 0.5))
            }
        }
        return out
    }

    private static func parseHexByte(_ raw: String) -> Int {
        let cleaned =
            raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .filter { ch in
                switch ch {
                case "0"..."9", "A"..."F":
                    return true
                default:
                    return false
                }
            }
        if cleaned.isEmpty {
            return 0
        }
        let trimmed = cleaned.count > 2 ? String(cleaned.suffix(2)) : cleaned
        return Int(trimmed, radix: 16) ?? 0
    }

    private static func modifiedJulianDay(year: Int, month: Int, day: Int) -> Int {
        var y = year
        var m = month
        if m <= 2 {
            y -= 1
            m += 12
        }
        let a = y / 100
        let b = 2 - a + (a / 4)
        let jd = Int(
            Double(Int(365.25 * Double(y + 4716)))
                + Double(Int(30.6001 * Double(m + 1)))
                + Double(day + b) - 1524.5)
        return jd - 2_400_001
    }

    private static func parseRTPlusTags(
        text: String,
        format: String,
        snapshot: NowPlayingSnapshot? = nil
    ) -> [RTPlusTag] {
        if text.isEmpty {
            return []
        }
        if let snapshot, snapshot.hasContent, format.isEmpty {
            return parseRTPlusTagsFromSnapshot(text: text, snapshot: snapshot)
        }
        if format.isEmpty {
            return []
        }

        var escaped = NSRegularExpression.escapedPattern(for: format)
        let nowPlayingPattern = capturePattern(
            name: "now_playing",
            exactValue: snapshot?.display
        )
        let displayPattern = capturePattern(
            name: "display",
            exactValue: snapshot?.display
        )
        let artistPattern = capturePattern(
            name: "artist",
            exactValue: snapshot?.artist
        )
        let titlePattern = capturePattern(
            name: "title",
            exactValue: snapshot?.title
        )
        escaped = escaped.replacingOccurrences(
            of: "\\{now_playing\\}", with: nowPlayingPattern)
        escaped = escaped.replacingOccurrences(of: "\\{display\\}", with: displayPattern)
        escaped = escaped.replacingOccurrences(of: "\\{artist\\}", with: artistPattern)
        escaped = escaped.replacingOccurrences(of: "\\{title\\}", with: titlePattern)
        guard let regex = try? NSRegularExpression(pattern: escaped, options: []) else {
            return []
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: fullRange) else {
            return []
        }

        func makeTag(name: String, contentType: Int) -> RTPlusTag? {
            let range = match.range(withName: name)
            guard range.location != NSNotFound, range.length > 0 else { return nil }
            let start = max(0, min(63, range.location))
            let length = max(1, min(64 - start, range.length))
            return RTPlusTag(contentType: contentType, start: start, length: length)
        }

        var tags: [RTPlusTag] = []
        if let titleTag = makeTag(name: "title", contentType: 1) {
            tags.append(titleTag)
        }
        if tags.isEmpty, let nowPlayingTag = makeTag(name: "now_playing", contentType: 1) {
            tags.append(nowPlayingTag)
        }
        if tags.isEmpty, let displayTag = makeTag(name: "display", contentType: 1) {
            tags.append(displayTag)
        }
        if let artistTag = makeTag(name: "artist", contentType: 4) {
            tags.append(artistTag)
        }
        return tags.sorted {
            if $0.start == $1.start {
                return $0.contentType < $1.contentType
            }
            return $0.start < $1.start
        }
    }

    private static func expandNowPlayingMacros(_ text: String, snapshot: NowPlayingSnapshot) -> String {
        NowPlayingFormatter.expandTemplate(text, snapshot: snapshot)
    }

    private static func capturePattern(name: String, exactValue: String?) -> String {
        let trimmed = exactValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return "(?<\(name)>.+?)"
        }
        let escapedValue = NSRegularExpression.escapedPattern(for: trimmed)
        return "(?<\(name)>\(escapedValue))"
    }

    private static func parseRTPlusTagsFromSnapshot(
        text: String,
        snapshot: NowPlayingSnapshot
    ) -> [RTPlusTag] {
        let nsText = text as NSString

        func firstTag(for value: String, contentType: Int) -> RTPlusTag? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let range = nsText.range(of: trimmed)
            guard range.location != NSNotFound, range.length > 0 else { return nil }
            let start = max(0, min(63, range.location))
            let length = max(1, min(64 - start, range.length))
            return RTPlusTag(contentType: contentType, start: start, length: length)
        }

        var tags: [RTPlusTag] = []
        if let artistTag = firstTag(for: snapshot.artist, contentType: 4) {
            tags.append(artistTag)
        }
        if let titleTag = firstTag(for: snapshot.title, contentType: 1) {
            tags.append(titleTag)
        } else if let displayTag = firstTag(for: snapshot.display, contentType: 1) {
            tags.append(displayTag)
        }

        return tags.sorted {
            if $0.start == $1.start {
                return $0.contentType < $1.contentType
            }
            return $0.start < $1.start
        }
    }
}

final class MPXGenerator {
    struct AGCStatus {
        let enabled: Bool
        let detectorDB: Float
        let gainDB: Float
        let gateActive: Bool
    }

    struct FinalLimiterStatus {
        let enabled: Bool
        let gainReductionDB: Float
        let safetyGainReductionDB: Float
    }

    struct CompositeCalibrationStatus {
        let pilotPercent: Float
        let rdsPercent: Float
        let audioPeak: Float
        let budgetMarginDB: Float
    }

    private struct FinalCompositeThresholds {
        let effectiveThreshold: Float
        let preLimiterCeiling: Float
        let postLimiterCeiling: Float
    }

    private static let finalCompositePreLimiterHeadroom: Float = 0.040
    private static let finalCompositePostLimiterHeadroom: Float = 0.030
    private static let finalCompositePreLimiterFloor: Float = 0.18
    private static let finalCompositePostLimiterFloor: Float = 0.16

    private struct EncoderComplianceConfig {
        let programLowpassHz: Float
        let encoderLowpassHz: Float
        let hfGuardCrossoverHz: Float
    }

    struct RuntimeConfig {
        let inputGainDB: Float
        let outputGainDB: Float
        let finalDriveDB: Float
        let widebandAGCEnabled: Bool
        let widebandAGCTargetDB: Float
        let widebandAGCMaxGainDB: Float
        let widebandAGCMinGainDB: Float
        let widebandAGCAttackMS: Float
        let widebandAGCReleaseMS: Float
        let compositeLimiterEnabled: Bool
        let mpxDeviationKHz: Float
        let orbassEnabled: Bool
        let orbassAmount: Float
        let orbassHarmonics: Float
        let orbassDrive: Float
        let orbassDensity: Float
        let orbassSubharmonicsEnabled: Bool
        let orbassSubharmonicsAmount: Float
        let orbassFreqHz: Float
        let stereoWidenEnabled: Bool
        let monoBassEnabled: Bool
        let monoBassFreqHz: Float
        let widenWidth: Float
        let widenCenter: Float
        let widenMix: Float
        let multibandEnabled: Bool
        let multibandMode: Int
        let multibandMakeupDB: Float
        let multibandKneeDB: Float
        let multibandLinkStrength: Float
        let multibandReleaseProgramDependent: Bool
        let multibandX1Hz: Float
        let multibandX2Hz: Float
        let multibandX3Hz: Float
        let multibandX4Hz: Float
        let multibandLowThresholdDB: Float
        let multibandMidThresholdDB: Float
        let multibandHighThresholdDB: Float
        let multibandLowRatio: Float
        let multibandMidRatio: Float
        let multibandHighRatio: Float
        let multibandLowAttackMS: Float
        let multibandMidAttackMS: Float
        let multibandHighAttackMS: Float
        let multibandLowReleaseMS: Float
        let multibandMidReleaseMS: Float
        let multibandHighReleaseMS: Float
    }

    private var sampleRate: Float
    private let preemphasisUS: Int
    private let toneFreq: Float
    private let toneMode: String
    private let monoMode: Bool
    private let processingBypass: Bool
    private let pilotLevel: Float
    private let pilotInjectionPercent: Float
    private let rdsInjectionPercent: Float
    private let sumLevel: Float
    private let diffLevel: Float
    private var inputGain: Float
    private var outputGain: Float
    private var finalDrive: Float
    private let limitEnabled: Bool
    private let threshold: Float
    private var deviationScale: Float
    private let programLowpassHz: Float
    private let encoderHFGuardEnabled: Bool

    private var widebandAGCEnabled: Bool
    private var widebandAGCTargetDB: Float
    private var widebandAGCMaxGainDB: Float
    private var widebandAGCMinGainDB: Float
    private var widebandAGCAttackMS: Float
    private var widebandAGCReleaseMS: Float
    private var widebandAGC = WidebandAGCRider()

    private let hpfHz: Float
    private let hfTrimDB: Float
    private let hfTrimHz: Float
    private var inputHPF = StereoBiquad()
    private var hfTrim = StereoBiquad()

    private let limitLookaheadEnabled: Bool
    private let limitLookaheadMS: Float
    private var lookaheadLimiter = LookaheadLimiter()

    private var orbassEnabled: Bool
    private var orbassAmount: Float
    private var orbassHarmonics: Float
    private var orbassDrive: Float
    private var orbassDensity: Float
    private var orbassSubharmonicsEnabled: Bool
    private var orbassSubharmonicsAmount: Float
    private var orbassFreqHz: Float
    private var orbassLP = OnePoleLP()
    private var orbassSubLP = OnePoleLP()
    private var orbassHarmHPF = Biquad()
    private var orbassHarmLPF = Biquad()
    private var orbassSubPrevSample: Float = 0.0
    private var orbassSubPhase: Int = 0
    private let orbassTargetRatio: Float = 0.42
    private let orbassRatioDeadband: Float = 0.05
    private var orbassRatioEst: Float = 0.42
    private var orbassAdaptiveTarget: Float = 0.0
    private var orbassAdaptiveGain: Float = 0.0
    private var orbassLevelEst: Float = 1e-3
    private let orbassHoldSeconds: Float = 0.12
    private var orbassHoldRemaining: Float = 0.0
    private var orbassMakeupGain: Float = 1.0

    private var multibandEnabled: Bool
    private var multibandMode: Int
    private var multibandMakeup: Float
    private var multibandKneeDB: Float
    private var multibandLinkStrength: Float
    private var multibandReleaseProgramDependent: Bool
    private var multibandX1Hz: Float
    private var multibandX2Hz: Float
    private var multibandX3Hz: Float
    private var multibandX4Hz: Float
    private var multibandLowThresholdDB: Float
    private var multibandMidThresholdDB: Float
    private var multibandHighThresholdDB: Float
    private var multibandLowRatio: Float
    private var multibandMidRatio: Float
    private var multibandHighRatio: Float
    private var multibandLowAttackMS: Float
    private var multibandMidAttackMS: Float
    private var multibandHighAttackMS: Float
    private var multibandLowReleaseMS: Float
    private var multibandMidReleaseMS: Float
    private var multibandHighReleaseMS: Float

    private var mb3Split1 = StereoLinkwitzRiley4()
    private var mb3Split2 = StereoLinkwitzRiley4()
    private var mbLowCompL = MonoCompressor()
    private var mbLowCompR = MonoCompressor()
    private var mbMidCompL = MonoCompressor()
    private var mbMidCompR = MonoCompressor()
    private var mbHighCompL = MonoCompressor()
    private var mbHighCompR = MonoCompressor()

    private var mb5Split1 = StereoLinkwitzRiley4()
    private var mb5Split2 = StereoLinkwitzRiley4()
    private var mb5Split3 = StereoLinkwitzRiley4()
    private var mb5Split4 = StereoLinkwitzRiley4()
    private var mb5Comp1L = MonoCompressor()
    private var mb5Comp1R = MonoCompressor()
    private var mb5Comp2L = MonoCompressor()
    private var mb5Comp2R = MonoCompressor()
    private var mb5Comp3L = MonoCompressor()
    private var mb5Comp3R = MonoCompressor()
    private var mb5Comp4L = MonoCompressor()
    private var mb5Comp4R = MonoCompressor()
    private var mb5Comp5L = MonoCompressor()
    private var mb5Comp5R = MonoCompressor()

    private var stereoWidenEnabled: Bool
    private var monoBassEnabled: Bool
    private var monoBassFreqHz: Float
    private var widenWidth: Float
    private var widenCenter: Float
    private var widenMix: Float
    private var monoBassSideLP = Biquad()
    private var widenSideHP = Biquad()
    private var stereoProtectInputMidEnv: Float = 0.0
    private var stereoProtectInputSideEnv: Float = 0.0
    private var stereoProtectMidEnv: Float = 0.0
    private var stereoProtectSideEnv: Float = 0.0
    private var stereoProtectGain: Float = 1.0
    private var stereoProtectAttackCoeff: Float = 0.0
    private var stereoProtectReleaseCoeff: Float = 0.0
    private var rdsCoder: BasicRDSCoder?

    private var compositeLimiterEnabled: Bool
    private var compositeLimiter = CompositeTruePeakLimiter()

    private var toneStep: Float
    private var tonePhase: Float = 0.0
    private var pilotOsc = SineCosOsc()
    private var pilotPhaseForRDS: Float = 0.0
    private var subPhase: Float = 0.0

    private var pilotSupported: Bool = false
    private var stereoSubcarrierSupported: Bool = false
    private var rdsSupported: Bool = false

    private var preSum = PreemphasisFilter()
    private var preDiff = PreemphasisFilter()
    private var programLP = ProgramLowpass()
    private var encoderProgramLP = ProgramLowpass()
    private var encoderHFGuardSplit = StereoLinkwitzRiley4()
    private var encoderHFGuardEnv: Float = 0.0
    private var encoderHFGuardGain: Float = 1.0
    private var encoderHFGuardAttackCoeff: Float = 0.0
    private var encoderHFGuardReleaseCoeff: Float = 0.0
    private var compositeAudioSmoother = OnePoleLP()
    private var compositeAudioSmootherEnabled: Bool = false
    private var monitorLPRLP = BiquadCascade6()
    private var monitorDiffBandHP = BiquadCascade6()
    private var monitorDiffBandLP = BiquadCascade6()
    private var monitorDiffLP = BiquadCascade6()
    private var monitorRFNotchPilot = Biquad()
    private var monitorRFNotchRDS = Biquad()
    private var monitorPilotNotchL = Biquad()
    private var monitorPilotNotchR = Biquad()
    private var monitorDeemphasisL = DeemphasisFilter()
    private var monitorDeemphasisR = DeemphasisFilter()
    private var lastSubcarrierSample: Float = 0.0
    private var audioCompositePeakState: Float = 0.0
    private var audioCompositePeakDecayCoeff: Float = 0.0
    private var subcarrierReservationEnv: Float = 0.0
    private var subcarrierReservationAttackCoeff: Float = 0.0
    private var subcarrierReservationReleaseCoeff: Float = 0.0
    private var monitorNoiseGateGain: Float = 0.0
    private var monitorNoiseGateOpen: Bool = false
    private var lastProgramActivity: Float = 0.0
    private struct ProgramStereoState {
        var left: Float
        var right: Float
        var referenceLeft: Float
        var referenceRight: Float
        var inputActivity: Float
    }

    private struct CompositeComponents {
        var base: Float
        var diff: Float
        var sub: Float
        var pilot: Float
        var rds: Float
    }

    private struct StereoImageState {
        var left: Float
        var right: Float
    }
    private var monitorProgramEnv: Float = 0.0
    private var monitorProgramNoiseFloor: Float = 0.0
    private var monitorExpectedSideEnv: Float = 0.0
    private var monitorExpectedSideAttackCoeff: Float = 0.0
    private var monitorExpectedSideReleaseCoeff: Float = 0.0
    private var monitorCollapseHoldSamples: Int = 0
    private var monitorCollapseCooldownSamples: Int = 0

    init(config: AppConfig, sampleRate: Double, nowPlayingState: NowPlayingState? = nil) {
        self.sampleRate = Float(max(8_000.0, sampleRate))
        self.preemphasisUS = config.preemphasisUS
        self.toneFreq = Float(config.testToneFreq)
        self.toneMode = config.testToneMode.lowercased()
        self.monoMode = config.monoMode
        self.processingBypass = config.processingBypass
        self.pilotLevel = Float(config.pilotLevel)
        self.pilotInjectionPercent = Float(config.pilotLevel * 100.0)
        self.rdsInjectionPercent = Float(max(0.0, config.rdsLevel / 75.0 * 100.0))
        self.sumLevel = Float(config.sumLevel)
        self.diffLevel = Float(config.diffLevel)
        self.inputGain = powf(10.0, Float(config.inputGainDB) / 20.0)
        self.outputGain = powf(10.0, Float(config.outputGainDB) / 20.0)
        self.finalDrive = powf(10.0, Float(config.finalDriveDB) / 20.0)
        self.limitEnabled = config.limitMPX
        self.threshold = clampf(Float(config.limitThreshold), 0.5, 0.999)
        self.deviationScale = Float(config.mpxDeviationKHz / 75.0)
        self.programLowpassHz = Float(config.programLowpassHz)
        self.encoderHFGuardEnabled = config.preemphasisUS > 0

        self.widebandAGCEnabled = config.widebandAGCEnabled
        self.widebandAGCTargetDB = Float(config.widebandAGCTargetDB)
        self.widebandAGCMaxGainDB = Float(config.widebandAGCMaxGainDB)
        self.widebandAGCMinGainDB = Float(config.widebandAGCMinGainDB)
        self.widebandAGCAttackMS = Float(config.widebandAGCAttackMS)
        self.widebandAGCReleaseMS = Float(config.widebandAGCReleaseMS)

        self.hpfHz = clampf(Float(config.hpfHz), 10.0, 200.0)
        self.hfTrimDB = clampf(Float(config.hfTrimDB), -12.0, 0.0)
        self.hfTrimHz = clampf(Float(config.hfTrimHz), 500.0, 12_000.0)

        self.limitLookaheadEnabled = config.limitLookaheadEnabled
        self.limitLookaheadMS = clampf(Float(config.limitLookaheadMS), 0.0, 20.0)
        self.compositeLimiterEnabled = config.compositeLimiterEnabled

        self.orbassEnabled = config.orbassEnabled
        self.orbassAmount = clampf(Float(config.orbassAmount), 0.0, 1.0)
        self.orbassHarmonics = clampf(Float(config.orbassHarmonics), 0.0, 1.0)
        self.orbassDrive = clampf(Float(config.orbassDrive), 0.0, 2.5)
        self.orbassDensity = clampf(Float(config.orbassDensity), 0.0, 1.0)
        self.orbassSubharmonicsEnabled = config.orbassSubharmonicsEnabled
        self.orbassSubharmonicsAmount = clampf(Float(config.orbassSubharmonicsAmount), 0.0, 1.0)
        self.orbassFreqHz = clampf(Float(config.orbassFreqHz), 45.0, 220.0)

        self.multibandEnabled = config.multibandEnabled
        self.multibandMode = (config.multibandMode == 5) ? 5 : 3
        self.multibandMakeup = powf(10.0, Float(config.multibandMakeupDB) / 20.0)
        self.multibandKneeDB = clampf(Float(config.multibandKneeDB), 0.0, 12.0)
        self.multibandLinkStrength = clampf(Float(config.multibandLinkStrength), 0.0, 1.0)
        self.multibandReleaseProgramDependent = config.multibandReleaseProgramDependent
        let crossovers = Self.resolveMultibandCrossovers(
            sampleRate: self.sampleRate,
            x1: Float(config.multibandX1Hz),
            x2: Float(config.multibandX2Hz),
            x3: Float(config.multibandX3Hz),
            x4: Float(config.multibandX4Hz)
        )
        self.multibandX1Hz = crossovers.x1
        self.multibandX2Hz = crossovers.x2
        self.multibandX3Hz = crossovers.x3
        self.multibandX4Hz = crossovers.x4
        self.multibandLowThresholdDB = Float(config.multibandLowThresholdDB)
        self.multibandMidThresholdDB = Float(config.multibandMidThresholdDB)
        self.multibandHighThresholdDB = Float(config.multibandHighThresholdDB)
        self.multibandLowRatio = Float(config.multibandLowRatio)
        self.multibandMidRatio = Float(config.multibandMidRatio)
        self.multibandHighRatio = Float(config.multibandHighRatio)
        self.multibandLowAttackMS = Float(config.multibandLowAttackMS)
        self.multibandMidAttackMS = Float(config.multibandMidAttackMS)
        self.multibandHighAttackMS = Float(config.multibandHighAttackMS)
        self.multibandLowReleaseMS = Float(config.multibandLowReleaseMS)
        self.multibandMidReleaseMS = Float(config.multibandMidReleaseMS)
        self.multibandHighReleaseMS = Float(config.multibandHighReleaseMS)

        self.stereoWidenEnabled = config.stereoWidenEnabled
        self.monoBassEnabled = config.monoBassEnabled
        self.monoBassFreqHz = clampf(Float(config.monoBassFreqHz), 60.0, 250.0)
        self.widenWidth = clampf(Float(config.stereoWidenWidth), 0.0, 1.0)
        self.widenCenter = clampf(Float(config.stereoWidenCenter), 0.0, 1.0)
        self.widenMix = clampf(Float(config.stereoWidenMix), 0.0, 1.0)
        self.rdsCoder = BasicRDSCoder(
            config: config,
            sampleRate: self.sampleRate,
            nowPlayingState: nowPlayingState
        )

        self.toneStep = 0.0

        preSum.configure(tauUS: preemphasisUS, sampleRate: self.sampleRate)
        preDiff.configure(tauUS: preemphasisUS, sampleRate: self.sampleRate)
        applyEncoderComplianceConfiguration(sampleRate: self.sampleRate)

        widebandAGC.configure(
            sampleRate: self.sampleRate,
            targetDB: widebandAGCTargetDB,
            attackMS: widebandAGCAttackMS,
            releaseMS: widebandAGCReleaseMS,
            minGainDB: widebandAGCMinGainDB,
            maxGainDB: widebandAGCMaxGainDB
        )
        inputHPF.configureHighpass(cutoffHz: hpfHz, sampleRate: self.sampleRate)
        hfTrim.configureHighShelf(gainDB: hfTrimDB, cutoffHz: hfTrimHz, sampleRate: self.sampleRate)
        configureOrbassFilters()
        configureMultibandFilters()
        configureMultibandCompressors()
        configureStereoWidener()
        lookaheadLimiter.configure(
            sampleRate: self.sampleRate,
            lookaheadMS: limitLookaheadMS,
            threshold: threshold,
            enabled: limitEnabled && limitLookaheadEnabled
        )
        compositeLimiter.configure(
            sampleRate: self.sampleRate,
            threshold: min(0.96, threshold * 0.965),
            releaseMS: 32.0
        )
        updateDerivedRates()
        configureMonitorDemod()
    }

    func setSampleRate(_ newSampleRate: Double) {
        let sr = Float(max(8_000.0, newSampleRate))
        if fabsf(sr - sampleRate) < 0.1 {
            return
        }
        sampleRate = sr
        preSum.configure(tauUS: preemphasisUS, sampleRate: sampleRate)
        preDiff.configure(tauUS: preemphasisUS, sampleRate: sampleRate)
        applyEncoderComplianceConfiguration(sampleRate: sampleRate)
        widebandAGC.configure(
            sampleRate: sampleRate,
            targetDB: widebandAGCTargetDB,
            attackMS: widebandAGCAttackMS,
            releaseMS: widebandAGCReleaseMS,
            minGainDB: widebandAGCMinGainDB,
            maxGainDB: widebandAGCMaxGainDB
        )
        inputHPF.configureHighpass(cutoffHz: hpfHz, sampleRate: sampleRate)
        hfTrim.configureHighShelf(gainDB: hfTrimDB, cutoffHz: hfTrimHz, sampleRate: sampleRate)
        configureOrbassFilters()
        configureMultibandFilters()
        configureMultibandCompressors()
        configureStereoWidener()
        lookaheadLimiter.configure(
            sampleRate: sampleRate,
            lookaheadMS: limitLookaheadMS,
            threshold: threshold,
            enabled: limitEnabled && limitLookaheadEnabled
        )
        compositeLimiter.configure(
            sampleRate: sampleRate,
            threshold: min(0.96, threshold * 0.965),
            releaseMS: 32.0
        )
        rdsCoder?.setSampleRate(sampleRate)
        updateDerivedRates()
        configureMonitorDemod()
    }

    func applyRuntimeConfig(_ config: RuntimeConfig) {
        inputGain = powf(10.0, config.inputGainDB / 20.0)
        outputGain = powf(10.0, config.outputGainDB / 20.0)
        finalDrive = powf(10.0, config.finalDriveDB / 20.0)
        deviationScale = config.mpxDeviationKHz / 75.0
        compositeLimiterEnabled = config.compositeLimiterEnabled

        let agcChanged =
            widebandAGCEnabled != config.widebandAGCEnabled
            || fabsf(widebandAGCTargetDB - config.widebandAGCTargetDB) > 0.0001
            || fabsf(widebandAGCMaxGainDB - config.widebandAGCMaxGainDB) > 0.0001
            || fabsf(widebandAGCMinGainDB - config.widebandAGCMinGainDB) > 0.0001
            || fabsf(widebandAGCAttackMS - config.widebandAGCAttackMS) > 0.0001
            || fabsf(widebandAGCReleaseMS - config.widebandAGCReleaseMS) > 0.0001

        widebandAGCEnabled = config.widebandAGCEnabled
        widebandAGCTargetDB = config.widebandAGCTargetDB
        widebandAGCMaxGainDB = config.widebandAGCMaxGainDB
        widebandAGCMinGainDB = config.widebandAGCMinGainDB
        widebandAGCAttackMS = config.widebandAGCAttackMS
        widebandAGCReleaseMS = config.widebandAGCReleaseMS

        if agcChanged {
            widebandAGC.configure(
                sampleRate: sampleRate,
                targetDB: widebandAGCTargetDB,
                attackMS: widebandAGCAttackMS,
                releaseMS: widebandAGCReleaseMS,
                minGainDB: widebandAGCMinGainDB,
                maxGainDB: widebandAGCMaxGainDB
            )
        }

        let orbassFiltersChanged =
            orbassEnabled != config.orbassEnabled
            || fabsf(orbassFreqHz - config.orbassFreqHz) > 0.0001
        orbassEnabled = config.orbassEnabled
        orbassAmount = clampf(config.orbassAmount, 0.0, 1.0)
        orbassHarmonics = clampf(config.orbassHarmonics, 0.0, 1.0)
        orbassDrive = clampf(config.orbassDrive, 0.0, 2.5)
        orbassDensity = clampf(config.orbassDensity, 0.0, 1.0)
        orbassSubharmonicsEnabled = config.orbassSubharmonicsEnabled
        orbassSubharmonicsAmount = clampf(config.orbassSubharmonicsAmount, 0.0, 1.0)
        orbassFreqHz = clampf(config.orbassFreqHz, 45.0, 220.0)
        if orbassFiltersChanged {
            configureOrbassFilters()
        }

        let stereoImageChanged =
            stereoWidenEnabled != config.stereoWidenEnabled
            || monoBassEnabled != config.monoBassEnabled
            || fabsf(monoBassFreqHz - config.monoBassFreqHz) > 0.0001
            || fabsf(widenWidth - config.widenWidth) > 0.0001
            || fabsf(widenCenter - config.widenCenter) > 0.0001
            || fabsf(widenMix - config.widenMix) > 0.0001
        stereoWidenEnabled = config.stereoWidenEnabled
        monoBassEnabled = config.monoBassEnabled
        monoBassFreqHz = clampf(config.monoBassFreqHz, 60.0, 250.0)
        widenWidth = clampf(config.widenWidth, 0.0, 1.0)
        widenCenter = clampf(config.widenCenter, 0.0, 1.0)
        widenMix = clampf(config.widenMix, 0.0, 1.0)
        if stereoImageChanged {
            configureStereoWidener()
        }

        let resolvedCrossovers = Self.resolveMultibandCrossovers(
            sampleRate: sampleRate,
            x1: config.multibandX1Hz,
            x2: config.multibandX2Hz,
            x3: config.multibandX3Hz,
            x4: config.multibandX4Hz
        )
        let multibandStructureChanged =
            multibandEnabled != config.multibandEnabled
            || multibandMode != (config.multibandMode == 5 ? 5 : 3)
            || fabsf(multibandX1Hz - resolvedCrossovers.x1) > 0.0001
            || fabsf(multibandX2Hz - resolvedCrossovers.x2) > 0.0001
            || fabsf(multibandX3Hz - resolvedCrossovers.x3) > 0.0001
            || fabsf(multibandX4Hz - resolvedCrossovers.x4) > 0.0001
        let multibandCompressorChanged =
            fabsf(multibandKneeDB - config.multibandKneeDB) > 0.0001
            || multibandReleaseProgramDependent != config.multibandReleaseProgramDependent
            || fabsf(multibandLowThresholdDB - config.multibandLowThresholdDB) > 0.0001
            || fabsf(multibandMidThresholdDB - config.multibandMidThresholdDB) > 0.0001
            || fabsf(multibandHighThresholdDB - config.multibandHighThresholdDB) > 0.0001
            || fabsf(multibandLowRatio - config.multibandLowRatio) > 0.0001
            || fabsf(multibandMidRatio - config.multibandMidRatio) > 0.0001
            || fabsf(multibandHighRatio - config.multibandHighRatio) > 0.0001
            || fabsf(multibandLowAttackMS - config.multibandLowAttackMS) > 0.0001
            || fabsf(multibandMidAttackMS - config.multibandMidAttackMS) > 0.0001
            || fabsf(multibandHighAttackMS - config.multibandHighAttackMS) > 0.0001
            || fabsf(multibandLowReleaseMS - config.multibandLowReleaseMS) > 0.0001
            || fabsf(multibandMidReleaseMS - config.multibandMidReleaseMS) > 0.0001
            || fabsf(multibandHighReleaseMS - config.multibandHighReleaseMS) > 0.0001
        multibandEnabled = config.multibandEnabled
        multibandMode = (config.multibandMode == 5) ? 5 : 3
        multibandMakeup = powf(10.0, config.multibandMakeupDB / 20.0)
        multibandKneeDB = clampf(config.multibandKneeDB, 0.0, 12.0)
        multibandLinkStrength = clampf(config.multibandLinkStrength, 0.0, 1.0)
        multibandReleaseProgramDependent = config.multibandReleaseProgramDependent
        multibandX1Hz = resolvedCrossovers.x1
        multibandX2Hz = resolvedCrossovers.x2
        multibandX3Hz = resolvedCrossovers.x3
        multibandX4Hz = resolvedCrossovers.x4
        multibandLowThresholdDB = config.multibandLowThresholdDB
        multibandMidThresholdDB = config.multibandMidThresholdDB
        multibandHighThresholdDB = config.multibandHighThresholdDB
        multibandLowRatio = config.multibandLowRatio
        multibandMidRatio = config.multibandMidRatio
        multibandHighRatio = config.multibandHighRatio
        multibandLowAttackMS = config.multibandLowAttackMS
        multibandMidAttackMS = config.multibandMidAttackMS
        multibandHighAttackMS = config.multibandHighAttackMS
        multibandLowReleaseMS = config.multibandLowReleaseMS
        multibandMidReleaseMS = config.multibandMidReleaseMS
        multibandHighReleaseMS = config.multibandHighReleaseMS
        if multibandStructureChanged {
            configureMultibandFilters()
        }
        if multibandStructureChanged || multibandCompressorChanged {
            configureMultibandCompressors()
        }
    }

    private func makeEncoderComplianceConfig() -> EncoderComplianceConfig {
        let effectiveProgramLP = effectiveProgramLowpassHz(
            configured: programLowpassHz,
            preemphasisUS: preemphasisUS
        )
        let effectiveEncoderLP = effectiveEncoderLowpassHz(
            configured: effectiveProgramLP,
            preemphasisUS: preemphasisUS
        )
        return EncoderComplianceConfig(
            programLowpassHz: effectiveProgramLP,
            encoderLowpassHz: effectiveEncoderLP,
            hfGuardCrossoverHz: 6_200.0
        )
    }

    private func applyEncoderComplianceConfiguration(sampleRate: Float) {
        let config = makeEncoderComplianceConfig()
        programLP.configure(cutoffHz: config.programLowpassHz, sampleRate: sampleRate)
        encoderProgramLP.configure(cutoffHz: config.encoderLowpassHz, sampleRate: sampleRate)
        encoderHFGuardSplit.configure(cutoffHz: config.hfGuardCrossoverHz, sampleRate: sampleRate)
    }

    var isProcessingBypassEnabled: Bool {
        processingBypass
    }

    var agcStatus: AGCStatus {
        let telemetry = widebandAGC.telemetry
        return AGCStatus(
            enabled: widebandAGCEnabled && !processingBypass,
            detectorDB: telemetry.detectorDB,
            gainDB: telemetry.gainDB,
            gateActive: telemetry.gateActive
        )
    }

    var finalLimiterStatus: FinalLimiterStatus {
        FinalLimiterStatus(
            enabled: compositeLimiterEnabled && !processingBypass,
            gainReductionDB: compositeLimiter.gainReductionDB,
            safetyGainReductionDB: (limitEnabled && !processingBypass)
                ? lookaheadLimiter.gainReductionDB : 0.0
        )
    }

    var compositeCalibrationStatus: CompositeCalibrationStatus {
        let calibration = Self.makeCompositeCalibration(
            audioPeakState: audioCompositePeakState,
            reservationEnv: subcarrierReservationEnv,
            outputGain: outputGain
        )
        return CompositeCalibrationStatus(
            pilotPercent: monoMode ? 0.0 : pilotInjectionPercent,
            rdsPercent: monoMode ? 0.0 : rdsInjectionPercent,
            audioPeak: calibration.audioPeak,
            budgetMarginDB: calibration.budgetMarginDB
        )
    }

    private func updateDerivedRates() {
        toneStep = twoPi * toneFreq / sampleRate
        pilotOsc.configure(freq: pilotFreq, sampleRate: sampleRate)
        let sr = max(8_000.0, sampleRate)
        audioCompositePeakDecayCoeff = expf(-1.0 / (0.250 * sr))
        subcarrierReservationAttackCoeff = expf(-1.0 / (0.0005 * sr))
        subcarrierReservationReleaseCoeff = expf(-1.0 / (0.012 * sr))
        encoderHFGuardEnv = 0.0
        encoderHFGuardGain = 1.0
        encoderHFGuardAttackCoeff = expf(-1.0 / (0.004 * sr))
        encoderHFGuardReleaseCoeff = expf(-1.0 / (0.080 * sr))
        let nyquist = (sampleRate * 0.5) - 100.0
        if nyquist > 56_000.0 {
            compositeAudioSmoother.configure(
                cutoffHz: min(54_000.0, nyquist - 1_500.0),
                sampleRate: sampleRate
            )
            compositeAudioSmootherEnabled = true
        } else {
            compositeAudioSmootherEnabled = false
            compositeAudioSmoother.state = 0.0
        }
        pilotSupported = nyquist > (pilotFreq + 100.0)
        stereoSubcarrierSupported = nyquist > (subcarrierFreq + 100.0)
        rdsSupported = nyquist > 57_100.0

        updateMonitorRecoveryRates()
    }

    private func updateMonitorRecoveryRates() {
        let sr = max(8_000.0, sampleRate)
        monitorExpectedSideAttackCoeff = expf(-1.0 / (0.010 * sr))
        monitorExpectedSideReleaseCoeff = expf(-1.0 / (0.260 * sr))
    }

    private func configureStereoWidener() {
        let sr = max(8_000.0, sampleRate)
        monoBassSideLP.configureLowpass(cutoffHz: monoBassFreqHz, sampleRate: sr, q: 0.7071068)
        widenSideHP.configureHighpass(cutoffHz: 115.0, sampleRate: sr, q: 0.7071068)
        stereoProtectInputMidEnv = 0.0
        stereoProtectInputSideEnv = 0.0
        stereoProtectMidEnv = 0.0
        stereoProtectSideEnv = 0.0
        stereoProtectGain = 1.0
        stereoProtectAttackCoeff = expf(-1.0 / (0.010 * sr))
        stereoProtectReleaseCoeff = expf(-1.0 / (0.300 * sr))
    }

    private func configureMonitorDemod() {
        let sr = max(8_000.0, sampleRate)
        let nyquist = max(6_000.0, (sr * 0.5) - 200.0)

        monitorLPRLP.configureLowpass(cutoffHz: 15_000.0, sampleRate: sr)

        monitorDiffBandHP.configureHighpass(cutoffHz: 23_000.0, sampleRate: sr)
        let diffHigh = min(52_000.0, nyquist)
        if diffHigh > 24_000.0 {
            monitorDiffBandLP.configureLowpass(cutoffHz: diffHigh, sampleRate: sr)
        } else {
            monitorDiffBandLP.configureIdentity()
        }

        monitorDiffLP.configureLowpass(cutoffHz: 15_000.0, sampleRate: sr)

        if nyquist > (pilotFreq + 100.0) {
            monitorRFNotchPilot.configureNotch(freqHz: pilotFreq, sampleRate: sr, q: 18.0)
            monitorPilotNotchL.configureNotch(freqHz: pilotFreq, sampleRate: sr, q: 24.0)
            monitorPilotNotchR.configureNotch(freqHz: pilotFreq, sampleRate: sr, q: 24.0)
        } else {
            monitorRFNotchPilot.configureIdentity()
            monitorPilotNotchL.configureIdentity()
            monitorPilotNotchR.configureIdentity()
        }

        if nyquist > 57_100.0 {
            monitorRFNotchRDS.configureNotch(freqHz: 57_000.0, sampleRate: sr, q: 22.0)
        } else {
            monitorRFNotchRDS.configureIdentity()
        }

        monitorDeemphasisL.configure(tauUS: preemphasisUS, sampleRate: sr)
        monitorDeemphasisR.configure(tauUS: preemphasisUS, sampleRate: sr)
        lastSubcarrierSample = 0.0
        monitorNoiseGateGain = 0.0
        monitorNoiseGateOpen = false
        lastProgramActivity = 0.0
        monitorProgramEnv = 0.0
        monitorProgramNoiseFloor = 0.0
        monitorCollapseHoldSamples = 0
    }

    private func demodulateMonitorFromMPXSample(_ mpx: Float) -> (Float, Float) {
        var monSrc = monitorRFNotchPilot.process(mpx)
        monSrc = monitorRFNotchRDS.process(monSrc)

        let lpr = monitorLPRLP.process(monSrc)

        let dsbHP = monitorDiffBandHP.process(monSrc)
        let dsb = monitorDiffBandLP.process(dsbHP)
        var diff = 2.0 * dsb * lastSubcarrierSample
        diff = monitorDiffLP.process(diff)
        diff = -diff

        var left = lpr + diff
        var right = lpr - diff

        left = monitorPilotNotchL.process(left)
        right = monitorPilotNotchR.process(right)
        left = monitorDeemphasisL.process(left)
        right = monitorDeemphasisR.process(right)

        let sr = max(8_000.0, sampleRate)
        let activity = max(0.0, lastProgramActivity)

        let envAttackS: Float = 0.010
        let envReleaseS: Float = 0.180
        let envAttackCoeff = expf(-1.0 / (sr * envAttackS))
        let envReleaseCoeff = expf(-1.0 / (sr * envReleaseS))
        let envCoeff = activity > monitorProgramEnv ? envAttackCoeff : envReleaseCoeff
        monitorProgramEnv = (envCoeff * monitorProgramEnv) + ((1.0 - envCoeff) * activity)

        // Track the long-term idle floor to reject ADC hiss when no real program is present.
        let floorTarget = monitorProgramEnv
        if !monitorNoiseGateOpen || floorTarget <= (monitorProgramNoiseFloor * 1.4) {
            let floorRiseS: Float = 3.0
            let floorFallS: Float = 0.50
            let floorS = floorTarget > monitorProgramNoiseFloor ? floorRiseS : floorFallS
            let floorCoeff = expf(-1.0 / (sr * floorS))
            monitorProgramNoiseFloor =
                (floorCoeff * monitorProgramNoiseFloor) + ((1.0 - floorCoeff) * floorTarget)
        }

        let openThreshold = max(0.00016, monitorProgramNoiseFloor * 2.3)
        let closeThreshold = max(0.00008, monitorProgramNoiseFloor * 1.6)
        if monitorNoiseGateOpen {
            if monitorProgramEnv < closeThreshold {
                monitorNoiseGateOpen = false
            }
        } else if monitorProgramEnv > openThreshold {
            monitorNoiseGateOpen = true
        }
        let targetGain: Float = monitorNoiseGateOpen ? 1.0 : 0.0
        let attackS: Float = 0.006
        let releaseS: Float = 0.140
        let timeConstant = targetGain > monitorNoiseGateGain ? attackS : releaseS
        let coeff = expf(-1.0 / (sr * timeConstant))
        monitorNoiseGateGain = (coeff * monitorNoiseGateGain) + ((1.0 - coeff) * targetGain)
        left *= monitorNoiseGateGain
        right *= monitorNoiseGateGain

        // Auto-recover demod state if decoded stereo collapses while encoded side persists.
        if monitorCollapseCooldownSamples > 0 {
            monitorCollapseCooldownSamples -= 1
        }
        let outSideAbs = fabsf((left - right) * 0.5)
        let expectedSide = monitorExpectedSideEnv
        let sidePresent = expectedSide > max(0.0012, monitorProgramEnv * 0.08)
        let collapsed = outSideAbs < (expectedSide * 0.12)
        if sidePresent && collapsed {
            monitorCollapseHoldSamples += 1
            if monitorCollapseCooldownSamples <= 0,
                monitorCollapseHoldSamples > Int(sr * 0.55)
            {
                configureMonitorDemod()
                monitorCollapseCooldownSamples = Int(sr * 2.0)
                monitorCollapseHoldSamples = 0
            }
        } else {
            monitorCollapseHoldSamples = max(0, monitorCollapseHoldSamples - 1)
        }

        return (clampf(left, -1.0, 1.0), clampf(right, -1.0, 1.0))
    }

    private func configureOrbassFilters() {
        let nyquist = max(200.0, (sampleRate * 0.5) - 200.0)
        let bassCutoff = clampf(orbassFreqHz, 45.0, nyquist)
        orbassLP.configure(cutoffHz: bassCutoff, sampleRate: sampleRate)
        let subCutoff = clampf(max(45.0, orbassFreqHz * 0.8), 45.0, nyquist)
        orbassSubLP.configure(cutoffHz: subCutoff, sampleRate: sampleRate)
        let harmHPFCutoff = clampf(max(120.0, orbassFreqHz * 1.6), 45.0, nyquist)
        let harmLPFMin = min(nyquist - 20.0, max(harmHPFCutoff + 20.0, 280.0))
        let harmLPFCutoff = clampf(max(280.0, orbassFreqHz * 5.0), harmLPFMin, nyquist)
        orbassHarmHPF.configureHighpass(cutoffHz: harmHPFCutoff, sampleRate: sampleRate)
        orbassHarmLPF.configureLowpass(cutoffHz: harmLPFCutoff, sampleRate: sampleRate)
    }

    private func configureMultibandFilters() {
        let x1 = clampf(multibandX1Hz, 40.0, max(60.0, (sampleRate * 0.5) - 300.0))
        let x2 = clampf(multibandX2Hz, x1 + 40.0, max(x1 + 60.0, (sampleRate * 0.5) - 200.0))
        let x3 = clampf(multibandX3Hz, x2 + 80.0, max(x2 + 100.0, (sampleRate * 0.5) - 120.0))
        let x4 = clampf(multibandX4Hz, x3 + 120.0, max(x3 + 140.0, (sampleRate * 0.5) - 60.0))

        mb3Split1.configure(cutoffHz: x1, sampleRate: sampleRate)
        mb3Split2.configure(cutoffHz: x2, sampleRate: sampleRate)

        mb5Split1.configure(cutoffHz: x1, sampleRate: sampleRate)
        mb5Split2.configure(cutoffHz: x2, sampleRate: sampleRate)
        mb5Split3.configure(cutoffHz: x3, sampleRate: sampleRate)
        mb5Split4.configure(cutoffHz: x4, sampleRate: sampleRate)
    }

    private func configureMultibandCompressors() {
        configureCompressorPair(
            left: &mbLowCompL,
            right: &mbLowCompR,
            thresholdDB: multibandLowThresholdDB,
            ratio: multibandLowRatio,
            attackMS: multibandLowAttackMS,
            releaseMS: releaseAdjusted(multibandLowReleaseMS)
        )
        configureCompressorPair(
            left: &mbMidCompL,
            right: &mbMidCompR,
            thresholdDB: multibandMidThresholdDB,
            ratio: multibandMidRatio,
            attackMS: multibandMidAttackMS,
            releaseMS: releaseAdjusted(multibandMidReleaseMS)
        )
        configureCompressorPair(
            left: &mbHighCompL,
            right: &mbHighCompR,
            thresholdDB: multibandHighThresholdDB,
            ratio: multibandHighRatio,
            attackMS: multibandHighAttackMS,
            releaseMS: releaseAdjusted(multibandHighReleaseMS)
        )

        let t2 = lerpf(multibandLowThresholdDB, multibandMidThresholdDB, 0.5)
        let t4 = lerpf(multibandMidThresholdDB, multibandHighThresholdDB, 0.5)
        let r2 = lerpf(multibandLowRatio, multibandMidRatio, 0.5)
        let r4 = lerpf(multibandMidRatio, multibandHighRatio, 0.5)
        let a2 = lerpf(multibandLowAttackMS, multibandMidAttackMS, 0.5)
        let a4 = lerpf(multibandMidAttackMS, multibandHighAttackMS, 0.5)
        let rel2 = releaseAdjusted(lerpf(multibandLowReleaseMS, multibandMidReleaseMS, 0.5))
        let rel4 = releaseAdjusted(lerpf(multibandMidReleaseMS, multibandHighReleaseMS, 0.5))

        configureCompressorPair(
            left: &mb5Comp1L,
            right: &mb5Comp1R,
            thresholdDB: multibandLowThresholdDB,
            ratio: multibandLowRatio,
            attackMS: multibandLowAttackMS,
            releaseMS: releaseAdjusted(multibandLowReleaseMS)
        )
        configureCompressorPair(
            left: &mb5Comp2L,
            right: &mb5Comp2R,
            thresholdDB: t2,
            ratio: r2,
            attackMS: a2,
            releaseMS: rel2
        )
        configureCompressorPair(
            left: &mb5Comp3L,
            right: &mb5Comp3R,
            thresholdDB: multibandMidThresholdDB,
            ratio: multibandMidRatio,
            attackMS: multibandMidAttackMS,
            releaseMS: releaseAdjusted(multibandMidReleaseMS)
        )
        configureCompressorPair(
            left: &mb5Comp4L,
            right: &mb5Comp4R,
            thresholdDB: t4,
            ratio: r4,
            attackMS: a4,
            releaseMS: rel4
        )
        configureCompressorPair(
            left: &mb5Comp5L,
            right: &mb5Comp5R,
            thresholdDB: multibandHighThresholdDB,
            ratio: multibandHighRatio,
            attackMS: multibandHighAttackMS,
            releaseMS: releaseAdjusted(multibandHighReleaseMS)
        )
    }

    private func releaseAdjusted(_ releaseMS: Float) -> Float {
        if multibandReleaseProgramDependent {
            return releaseMS * 1.1
        }
        return releaseMS
    }

    private func configureCompressorPair(
        left: inout MonoCompressor,
        right: inout MonoCompressor,
        thresholdDB: Float,
        ratio: Float,
        attackMS: Float,
        releaseMS: Float
    ) {
        left.configure(
            sampleRate: sampleRate,
            thresholdDB: thresholdDB,
            ratio: ratio,
            attackMS: attackMS,
            releaseMS: releaseMS,
            makeupDB: 0.0,
            kneeDB: multibandKneeDB
        )
        right.configure(
            sampleRate: sampleRate,
            thresholdDB: thresholdDB,
            ratio: ratio,
            attackMS: attackMS,
            releaseMS: releaseMS,
            makeupDB: 0.0,
            kneeDB: multibandKneeDB
        )
    }

    private static func resolveMultibandCrossovers(
        sampleRate: Float,
        x1: Float,
        x2: Float,
        x3: Float,
        x4: Float
    ) -> (x1: Float, x2: Float, x3: Float, x4: Float) {
        let nyquistLimit = max(600.0, (sampleRate * 0.5) - 100.0)
        let c1 = clampf(x1, 40.0, nyquistLimit - 400.0)
        var c2 = clampf(x2, c1 + 40.0, nyquistLimit - 300.0)
        var c3 = clampf(x3, c2 + 80.0, nyquistLimit - 200.0)
        var c4 = clampf(x4, c3 + 120.0, nyquistLimit - 100.0)
        if c2 <= c1 + 30.0 {
            c2 = c1 + 40.0
        }
        if c3 <= c2 + 60.0 {
            c3 = c2 + 80.0
        }
        if c4 <= c3 + 100.0 {
            c4 = c3 + 120.0
        }
        return (c1, c2, c3, c4)
    }

    func renderNonInterleaved(
        frameCount: Int,
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>
    ) {
        guard frameCount > 0 else { return }
        for i in 0..<frameCount {
            let tone = sinf(tonePhase)
            var l: Float
            var r: Float
            switch toneMode {
            case "left":
                l = tone
                r = 0.0
            case "right":
                l = 0.0
                r = tone
            case "stereo":
                l = tone
                r = -tone
            default:
                l = tone
                r = tone
            }
            let mpx = processSample(leftIn: l, rightIn: r)
            left[i] = mpx
            right[i] = mpx
        }
    }

    @inline(__always)
    func renderSingleSample(leftIn: Float, rightIn: Float) -> Float {
        processSample(leftIn: leftIn, rightIn: rightIn)
    }

    func renderFromInputInPlace(
        frameCount: Int,
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>
    ) {
        guard frameCount > 0 else { return }
        for i in 0..<frameCount {
            let mpx = processSample(leftIn: left[i], rightIn: right[i])
            left[i] = mpx
            right[i] = mpx
        }
    }

    func renderMonitorFromInputInPlace(
        frameCount: Int,
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>
    ) {
        guard frameCount > 0 else { return }
        for i in 0..<frameCount {
            var l = left[i] * inputGain
            var r = right[i] * inputGain
            if monoMode {
                let m = (l + r) * 0.5
                l = m
                r = m
            }
            left[i] = l
            right[i] = r
        }
    }

    func renderFromInputAndMonitorInPlace(
        frameCount: Int,
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        mpxLeft: UnsafeMutablePointer<Float>,
        mpxRight: UnsafeMutablePointer<Float>
    ) {
        guard frameCount > 0 else { return }
        for i in 0..<frameCount {
            let inputL = left[i]
            let inputR = right[i]

            let mpx = processSample(leftIn: inputL, rightIn: inputR)
            mpxLeft[i] = mpx
            mpxRight[i] = mpx

            let demod = demodulateMonitorFromMPXSample(mpx)
            left[i] = demod.0
            right[i] = demod.1
        }
    }

    func renderMonitorToneNonInterleaved(
        frameCount: Int,
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>
    ) {
        guard frameCount > 0 else { return }
        for i in 0..<frameCount {
            let tone = sinf(tonePhase)
            var l: Float
            var r: Float
            switch toneMode {
            case "left":
                l = tone
                r = 0.0
            case "right":
                l = 0.0
                r = tone
            case "stereo":
                l = tone
                r = -tone
            default:
                l = tone
                r = tone
            }
            if monoMode {
                let m = (l + r) * 0.5
                l = m
                r = m
            }
            left[i] = clampf(l * inputGain, -1.0, 1.0)
            right[i] = clampf(r * inputGain, -1.0, 1.0)
            tonePhase += toneStep
            if tonePhase >= twoPi { tonePhase -= twoPi }
        }
    }

    func renderToneAndMonitorNonInterleaved(
        frameCount: Int,
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        mpxLeft: UnsafeMutablePointer<Float>,
        mpxRight: UnsafeMutablePointer<Float>
    ) {
        guard frameCount > 0 else { return }
        for i in 0..<frameCount {
            let tone = sinf(tonePhase)
            var srcL: Float
            var srcR: Float
            switch toneMode {
            case "left":
                srcL = tone
                srcR = 0.0
            case "right":
                srcL = 0.0
                srcR = tone
            case "stereo":
                srcL = tone
                srcR = -tone
            default:
                srcL = tone
                srcR = tone
            }

            let mpx = processSample(leftIn: srcL, rightIn: srcR)
            mpxLeft[i] = mpx
            mpxRight[i] = mpx

            let demod = demodulateMonitorFromMPXSample(mpx)
            left[i] = demod.0
            right[i] = demod.1
        }
    }

    private func processSample(leftIn: Float, rightIn: Float) -> Float {
        // High-level chain order:
        // 1. Program-domain stereo processing (AGC, filtering, enhancement, multiband)
        // 2. Stereo-image protection and monitoring
        // 3. Composite component assembly (L+R, L-R, pilot, stereo subcarrier, RDS)
        // 4. Final composite loudness and safety limiting
        var stereo = processProgramStereo(leftIn: leftIn, rightIn: rightIn)

        if !processingBypass {
            let protected = protectStereoImage(
                inputL: stereo.referenceLeft,
                inputR: stereo.referenceRight,
                outputL: stereo.left,
                outputR: stereo.right
            )
            stereo.left = protected.0
            stereo.right = protected.1
        }

        updateStereoImageMonitor(left: stereo.left, right: stereo.right)

        let composite = makeCompositeComponents(
            left: stereo.left,
            right: stereo.right,
            inputActivity: stereo.inputActivity
        )

        return processFinalComposite(
            base: composite.base,
            diff: composite.diff,
            sub: composite.sub,
            pilot: composite.pilot,
            rds: composite.rds
        )
    }

    private func processProgramStereo(leftIn: Float, rightIn: Float) -> ProgramStereoState {
        var left = leftIn * inputGain
        var right = rightIn * inputGain

        if monoMode {
            let mono = (left + right) * 0.5
            left = mono
            right = mono
        }
        let inputActivity = max(fabsf(left), fabsf(right))

        if !processingBypass {
            if widebandAGCEnabled {
                let adjusted = widebandAGC.process(left: left, right: right)
                left = adjusted.0
                right = adjusted.1
            }

            let filteredInput = inputHPF.process(left: left, right: right)
            left = filteredInput.0
            right = filteredInput.1
        }

        let programBand = programLP.process(left: left, right: right)
        left = programBand.0
        right = programBand.1
        let referenceLeft = left
        let referenceRight = right

        if !processingBypass {
            let trimmed = hfTrim.process(left: left, right: right)
            left = trimmed.0
            right = trimmed.1

            if orbassEnabled {
                let orbassOut = processOrbass(left: left, right: right)
                left = orbassOut.0
                right = orbassOut.1
            }

            let stereoImage = processStereoImageStage(left: left, right: right)
            left = stereoImage.left
            right = stereoImage.right

            if multibandEnabled {
                let multiband = processMultibandStereo(left: left, right: right)
                left = multiband.0
                right = multiband.1
            }
        }

        if encoderHFGuardEnabled {
            let guarded = processEncoderHFGuard(left: left, right: right)
            left = guarded.0
            right = guarded.1
        }

        // Final encoder-facing bandwidth guard. This sits immediately ahead of
        // stereo encoding and pre-emphasis so later nonlinear stages do not
        // re-broaden the transmitted audio spectrum.
        let encoderBand = encoderProgramLP.process(left: left, right: right)
        left = encoderBand.0
        right = encoderBand.1

        return ProgramStereoState(
            left: left,
            right: right,
            referenceLeft: referenceLeft,
            referenceRight: referenceRight,
            inputActivity: inputActivity
        )
    }

    private func processEncoderHFGuard(left: Float, right: Float) -> (Float, Float) {
        let split = encoderHFGuardSplit.process(left: left, right: right)
        let lowL = split.0.0
        let highL = split.0.1
        let lowR = split.1.0
        let highR = split.1.1

        let hfDrive = max(fabsf(highL), fabsf(highR))
        encoderHFGuardEnv = Self.smoothEnvelope(
            current: encoderHFGuardEnv,
            input: hfDrive,
            attackCoeff: encoderHFGuardAttackCoeff,
            releaseCoeff: encoderHFGuardReleaseCoeff
        )

        let threshold: Float = 0.11
        let over = max(0.0, encoderHFGuardEnv - threshold)
        let targetReductionDB = min(2.0, over * 24.0)
        let targetGain = powf(10.0, -targetReductionDB / 20.0)
        encoderHFGuardGain = Self.smoothTowardTarget(
            current: encoderHFGuardGain,
            target: targetGain,
            attackCoeff: encoderHFGuardAttackCoeff,
            releaseCoeff: encoderHFGuardReleaseCoeff
        )

        return (
            lowL + (highL * encoderHFGuardGain),
            lowR + (highR * encoderHFGuardGain)
        )
    }

    private func makeCompositeComponents(left: Float, right: Float, inputActivity: Float)
        -> CompositeComponents
    {
        var base = ((left + right) * 0.5) * sumLevel
        var diff = monoMode ? 0.0 : (((right - left) * 0.5) * diffLevel)

        base = preSum.process(base)
        diff = preDiff.process(diff)
        lastProgramActivity = inputActivity

        tonePhase += toneStep
        if tonePhase >= twoPi { tonePhase -= twoPi }

        pilotOsc.step()
        pilotPhaseForRDS = pilotOsc.phase
        let stereoServicesEnabled = !monoMode
        let pilot = (stereoServicesEnabled && pilotSupported) ? (pilotOsc.s * pilotLevel) : 0.0
        let sub = (stereoServicesEnabled && stereoSubcarrierSupported) ? pilotOsc.sin2x() : 0.0
        lastSubcarrierSample = sub

        if stereoServicesEnabled {
            rdsCoder?.updateRDSPilotPhase(pilotPhaseForRDS)
        }
        let rds =
            (stereoServicesEnabled && rdsSupported) ? (rdsCoder?.nextSampleWithPilotLock() ?? 0.0)
            : 0.0

        return CompositeComponents(base: base, diff: diff, sub: sub, pilot: pilot, rds: rds)
    }

    private func processStereoImageStage(left: Float, right: Float) -> StereoImageState {
        var state = StereoImageState(left: left, right: right)

        if monoBassEnabled {
            let monoBass = processMonoBass(left: state.left, right: state.right)
            state.left = monoBass.0
            state.right = monoBass.1
        }

        if stereoWidenEnabled {
            let widened = processStereoWidener(left: state.left, right: state.right)
            state.left = widened.0
            state.right = widened.1
        }

        return state
    }

    private func processFinalComposite(
        base: Float,
        diff: Float,
        sub: Float,
        pilot: Float,
        rds: Float
    ) -> Float {
        let subcarriers = (pilot + rds) * deviationScale
        let reserved = updateSubcarrierReservation(subcarriers)
        let thresholds = Self.makeFinalCompositeThresholds(
            outputGain: outputGain,
            threshold: threshold,
            reserved: reserved
        )

        // Keep the loudness work in the audio composite before the calibrated
        // pilot/RDS subcarriers are added back into the final MPX waveform.
        let rawAudioComposite = Self.makeDrivenAudioComposite(
            base: base,
            diff: diff,
            sub: sub,
            deviationScale: deviationScale,
            finalDrive: finalDrive
        )
        var audioComposite = Self.softClipSafety(
            rawAudioComposite,
            threshold: thresholds.preLimiterCeiling
        )
        if compositeLimiterEnabled {
            audioComposite = compositeLimiter.process(audioComposite)
        }
        if compositeAudioSmootherEnabled {
            audioComposite = compositeAudioSmoother.process(audioComposite)
        }

        audioComposite = Self.softClipSafety(
            audioComposite,
            threshold: thresholds.postLimiterCeiling
        )

        let audioCompositeAbs = fabsf(audioComposite)
        audioCompositePeakState = max(
            audioCompositeAbs,
            audioCompositePeakState * audioCompositePeakDecayCoeff
        )

        var mpx = Self.makeOutputComposite(
            audioComposite: audioComposite,
            subcarriers: subcarriers,
            outputGain: outputGain
        )

        if limitEnabled {
            mpx = lookaheadLimiter.process(mpx)
            mpx = Self.softClipSafety(mpx, threshold: threshold)
        }

        return clampf(mpx, -1.0, 1.0)
    }

    @inline(__always)
    private func updateSubcarrierReservation(_ subcarriers: Float) -> Float {
        let subcarrierAbs = fabsf(subcarriers)
        subcarrierReservationEnv = Self.smoothEnvelope(
            current: subcarrierReservationEnv,
            input: subcarrierAbs,
            attackCoeff: subcarrierReservationAttackCoeff,
            releaseCoeff: subcarrierReservationReleaseCoeff
        )
        return subcarrierReservationEnv
    }

    private func updateStereoImageMonitor(left: Float, right: Float) {
        let postSideAbs = fabsf((left - right) * 0.5)
        monitorExpectedSideEnv = Self.smoothEnvelope(
            current: monitorExpectedSideEnv,
            input: postSideAbs,
            attackCoeff: monitorExpectedSideAttackCoeff,
            releaseCoeff: monitorExpectedSideReleaseCoeff
        )
    }

    private static func makeFinalCompositeThresholds(
        outputGain: Float,
        threshold: Float,
        reserved: Float
    ) -> FinalCompositeThresholds {
        let effectiveThreshold = threshold / max(1.0, outputGain)
        return FinalCompositeThresholds(
            effectiveThreshold: effectiveThreshold,
            preLimiterCeiling: max(
                Self.finalCompositePreLimiterFloor,
                effectiveThreshold - reserved - Self.finalCompositePreLimiterHeadroom
            ),
            postLimiterCeiling: max(
                Self.finalCompositePostLimiterFloor,
                effectiveThreshold - reserved - Self.finalCompositePostLimiterHeadroom
            )
        )
    }

    private static func makeCompositeCalibration(
        audioPeakState: Float,
        reservationEnv: Float,
        outputGain: Float
    ) -> (audioPeak: Float, budgetMarginDB: Float) {
        let postGain = max(0.0, outputGain)
        let reserved = max(0.0, min(1.2, reservationEnv * postGain))
        let audioPeak = audioPeakState * postGain
        let totalPeakBudget = max(1e-6, audioPeak + reserved)
        let budgetMarginDB = -20.0 * log10f(totalPeakBudget)
        return (audioPeak, budgetMarginDB)
    }

    @inline(__always)
    private static func makeDrivenAudioComposite(
        base: Float,
        diff: Float,
        sub: Float,
        deviationScale: Float,
        finalDrive: Float
    ) -> Float {
        (base + (diff * sub)) * deviationScale * finalDrive
    }

    @inline(__always)
    private static func makeOutputComposite(
        audioComposite: Float,
        subcarriers: Float,
        outputGain: Float
    ) -> Float {
        (audioComposite + subcarriers) * outputGain
    }

    @inline(__always)
    private static func smoothEnvelope(
        current: Float,
        input: Float,
        attackCoeff: Float,
        releaseCoeff: Float
    ) -> Float {
        let coeff = input > current ? attackCoeff : releaseCoeff
        return (coeff * current) + ((1.0 - coeff) * input)
    }

    @inline(__always)
    private static func smoothTowardTarget(
        current: Float,
        target: Float,
        attackCoeff: Float,
        releaseCoeff: Float
    ) -> Float {
        let coeff = target < current ? attackCoeff : releaseCoeff
        return (coeff * current) + ((1.0 - coeff) * target)
    }

    private func protectStereoImage(
        inputL: Float,
        inputR: Float,
        outputL: Float,
        outputR: Float
    ) -> (Float, Float) {
        let inputMid = (inputL + inputR) * 0.5
        let inputSide = (inputL - inputR) * 0.5
        let outputMid = (outputL + outputR) * 0.5
        let outputSide = (outputL - outputR) * 0.5

        let inputMidAbs = fabsf(inputMid)
        let inputSideAbs = fabsf(inputSide)
        let outputMidAbs = fabsf(outputMid)
        let outputSideAbs = fabsf(outputSide)

        stereoProtectInputMidEnv = Self.smoothEnvelope(
            current: stereoProtectInputMidEnv,
            input: inputMidAbs,
            attackCoeff: stereoProtectAttackCoeff,
            releaseCoeff: stereoProtectReleaseCoeff
        )
        stereoProtectInputSideEnv = Self.smoothEnvelope(
            current: stereoProtectInputSideEnv,
            input: inputSideAbs,
            attackCoeff: stereoProtectAttackCoeff,
            releaseCoeff: stereoProtectReleaseCoeff
        )
        stereoProtectMidEnv = Self.smoothEnvelope(
            current: stereoProtectMidEnv,
            input: outputMidAbs,
            attackCoeff: stereoProtectAttackCoeff,
            releaseCoeff: stereoProtectReleaseCoeff
        )
        stereoProtectSideEnv = Self.smoothEnvelope(
            current: stereoProtectSideEnv,
            input: outputSideAbs,
            attackCoeff: stereoProtectAttackCoeff,
            releaseCoeff: stereoProtectReleaseCoeff
        )

        let inputRatio = stereoProtectInputSideEnv / max(0.02, stereoProtectInputMidEnv)
        let configuredRatio = 0.70 + (widenWidth * 0.65)
        let allowedRatio = min(1.55, max(configuredRatio, inputRatio * 1.16))
        let allowedSide = max(0.008, stereoProtectMidEnv * allowedRatio)

        var targetGain: Float = 1.0
        if stereoProtectSideEnv > allowedSide {
            targetGain = clampf(allowedSide / max(1e-5, stereoProtectSideEnv), 0.0, 1.0)
        }

        stereoProtectGain = Self.smoothTowardTarget(
            current: stereoProtectGain,
            target: targetGain,
            attackCoeff: stereoProtectAttackCoeff,
            releaseCoeff: stereoProtectReleaseCoeff
        )

        let protectedSide = outputSide * stereoProtectGain
        return (outputMid + protectedSide, outputMid - protectedSide)
    }

    private func processStereoWidener(left: Float, right: Float) -> (Float, Float) {
        let mid = (left + right) * 0.5
        let side = (left - right) * 0.5
        let highSide = widenSideHP.process(side)
        let lowSide = side - highSide

        let sideGain = 1.0 + ((widenWidth - 0.5) * 1.35)
        let midGain = 1.0 + ((widenCenter - 0.5) * 0.35)
        let lowSideRetain = 0.34 + ((1.0 - widenWidth) * 0.16)

        var wetMid = mid * midGain
        var wetSide = (highSide * sideGain) + (lowSide * lowSideRetain)

        let inputEnergy = max(1e-6, (mid * mid) + (side * side))
        let wetEnergy = max(1e-6, (wetMid * wetMid) + (wetSide * wetSide))
        let norm = clampf(sqrtf(inputEnergy / wetEnergy), 0.90, 1.12)
        wetMid *= norm
        wetSide *= norm

        let wetLeft = wetMid + wetSide
        let wetRight = wetMid - wetSide
        let mixedLeft = lerpf(left, wetLeft, widenMix)
        let mixedRight = lerpf(right, wetRight, widenMix)
        return (mixedLeft, mixedRight)
    }

    private func processMonoBass(left: Float, right: Float) -> (Float, Float) {
        let mid = (left + right) * 0.5
        let side = (left - right) * 0.5
        let lowSide = monoBassSideLP.process(side)
        let highSide = side - lowSide
        let combinedSide = highSide
        return (mid + combinedSide, mid - combinedSide)
    }

    private func resetDynamicStereoState() {
        widebandAGC.reset()
        configureStereoWidener()

        orbassAdaptiveTarget = 0.0
        orbassAdaptiveGain = 0.0
        orbassRatioEst = orbassTargetRatio
        orbassLevelEst = 1e-3
        orbassHoldRemaining = 0.0
        orbassSubPrevSample = 0.0
        orbassSubPhase = 0
        orbassMakeupGain = 1.0

        mbLowCompL.detector.value = 0.0
        mbLowCompR.detector.value = 0.0
        mbMidCompL.detector.value = 0.0
        mbMidCompR.detector.value = 0.0
        mbHighCompL.detector.value = 0.0
        mbHighCompR.detector.value = 0.0
        mb5Comp1L.detector.value = 0.0
        mb5Comp1R.detector.value = 0.0
        mb5Comp2L.detector.value = 0.0
        mb5Comp2R.detector.value = 0.0
        mb5Comp3L.detector.value = 0.0
        mb5Comp3R.detector.value = 0.0
        mb5Comp4L.detector.value = 0.0
        mb5Comp4R.detector.value = 0.0
        mb5Comp5L.detector.value = 0.0
        mb5Comp5R.detector.value = 0.0
    }

    private func processOrbass(left: Float, right: Float) -> (Float, Float) {
        let mid = (left + right) * 0.5
        let side = (left - right) * 0.5
        let low = orbassLP.process(mid)

        let drive = clampf(orbassDrive, 0.0, 2.5)
        let density = clampf(orbassDensity, 0.0, 1.0)
        let amount = clampf(orbassAmount, 0.0, 1.0)
        let harmonics = clampf(orbassHarmonics, 0.0, 1.0)
        let subAmount = (orbassSubharmonicsEnabled ? orbassSubharmonicsAmount : 0.0)
        if amount <= 1e-4, harmonics <= 1e-4, subAmount <= 1e-4 {
            return (left, right)
        }

        let dt = 1.0 / max(8_000.0, sampleRate)
        let midAbs = max(1e-6, fabsf(mid))
        let bassAbs = fabsf(low)
        let gateFloor = max(0.012, orbassLevelEst * 0.18)
        if midAbs < gateFloor, bassAbs < gateFloor {
            return (left, right)
        }

        let lowRatio = bassAbs / max(midAbs, orbassLevelEst * 0.7, 0.02)
        let ratioAlpha = 1.0 - expf(-dt / 0.45)
        orbassRatioEst += (lowRatio - orbassRatioEst) * ratioAlpha
        let targetRatio = orbassTargetRatio + (0.06 * density)
        let deadband = max(0.03, orbassRatioDeadband - (0.015 * density))
        let lowEnter = max(0.05, targetRatio - deadband)
        let highExit = min(0.9, targetRatio + deadband)
        if orbassRatioEst < lowEnter {
            let deficit = (lowEnter - orbassRatioEst) / lowEnter
            orbassAdaptiveTarget = clampf(deficit, 0.0, 1.0)
        } else if orbassRatioEst > highExit {
            orbassAdaptiveTarget = 0.0
        }

        let levelAlpha = 1.0 - expf(-dt / 1.1)
        orbassLevelEst += (midAbs - orbassLevelEst) * levelAlpha
        let transientFactor = midAbs / max(1e-6, orbassLevelEst)
        if transientFactor > 3.5 {
            orbassHoldRemaining = orbassHoldSeconds
        }
        orbassHoldRemaining = max(0.0, orbassHoldRemaining - dt)
        if orbassHoldRemaining <= 0.0 {
            let adaptTau: Float = orbassAdaptiveTarget > orbassAdaptiveGain ? 1.2 : 2.8
            let adaptAlpha = 1.0 - expf(-dt / adaptTau)
            orbassAdaptiveGain += (orbassAdaptiveTarget - orbassAdaptiveGain) * adaptAlpha
        }
        let adaptive = clampf(orbassAdaptiveGain, 0.0, 1.0)

        let driveFactor = 0.55 + (0.42 * drive)
        let densityFactor = 0.50 + (0.42 * density)
        let boostGain = amount * driveFactor * densityFactor * (0.62 + (0.42 * adaptive))
        let lowBoost = low * boostGain

        let nlDrive = 1.0 + (drive * (1.0 + (amount * 1.8) + (harmonics * 1.4)))
        let harmonicSrc = tanhf(low * nlDrive) - tanhf(low * (0.65 + (0.18 * density)))
        let harmonicBand = orbassHarmLPF.process(orbassHarmHPF.process(harmonicSrc))
        let harmonicGain = harmonics * (0.28 + (0.34 * density)) * (0.62 + (0.36 * adaptive))
        var enhancement = lowBoost + (harmonicBand * harmonicGain)

        if subAmount > 1e-4 {
            let prev = orbassSubPrevSample
            if prev <= 0.0, low > 0.0 {
                orbassSubPhase ^= 1
            }
            orbassSubPrevSample = low
            let square: Float = orbassSubPhase == 0 ? -1.0 : 1.0
            let envelope = sqrtf(max(0.0, fabsf(low)))
            let subRaw = square * envelope
            let subWave = orbassSubLP.process(subRaw)
            let subGain = subAmount * (0.22 + (0.24 * density)) * (0.55 + (0.24 * drive))
            enhancement += subWave * subGain
        }

        let enhClip = max(0.52, 0.72 - (0.08 * density))
        let satEnhancement = enhClip * tanhf(enhancement / max(1e-4, enhClip))
        var midOut = mid + satEnhancement
        midOut *= 1.0 / (1.0 + (0.03 * amount) + (0.03 * subAmount))

        let outMidAbs = max(1e-6, fabsf(midOut))
        let targetMakeupPower = 0.34 + (0.08 * density)
        let targetMakeup = clampf(
            powf(midAbs / outMidAbs, targetMakeupPower),
            0.94,
            1.06 + (0.06 * density)
        )
        orbassMakeupGain = smoothOrbassGain(
            current: orbassMakeupGain,
            target: targetMakeup,
            attackMS: 45.0,
            releaseMS: 220.0
        )
        midOut *= orbassMakeupGain

        let outL = midOut + side
        let outR = midOut - side
        return Self.limitStereoDeltaPeak(
            inputLeft: left,
            inputRight: right,
            outputLeft: outL,
            outputRight: outR,
            allowedPeakScale: 1.04 + (0.04 * amount) + (0.04 * subAmount)
        )
    }

    private func smoothOrbassGain(current: Float, target: Float, attackMS: Float, releaseMS: Float)
        -> Float
    {
        let sr = max(8_000.0, sampleRate)
        let tauMS = target > current ? max(0.1, attackMS) : max(1.0, releaseMS)
        let coeff = expf(-1.0 / ((tauMS * 0.001) * sr))
        return (coeff * current) + ((1.0 - coeff) * target)
    }

    private static func limitStereoDeltaPeak(
        inputLeft: Float,
        inputRight: Float,
        outputLeft: Float,
        outputRight: Float,
        allowedPeakScale: Float
    ) -> (Float, Float) {
        let inPeak = max(max(fabsf(inputLeft), fabsf(inputRight)), 1e-6)
        let outPeak = max(max(fabsf(outputLeft), fabsf(outputRight)), 1e-6)
        let allowedPeak = inPeak * allowedPeakScale
        guard outPeak > allowedPeak else {
            return (outputLeft, outputRight)
        }

        let scale = allowedPeak / outPeak
        return (
            inputLeft + ((outputLeft - inputLeft) * scale),
            inputRight + ((outputRight - inputRight) * scale)
        )
    }

    private func processMultibandStereo(left: Float, right: Float) -> (Float, Float) {
        if multibandMode == 5 {
            return processFiveBandMultiband(left: left, right: right)
        }
        return processThreeBandMultiband(left: left, right: right)
    }

    private func processThreeBandMultiband(left: Float, right: Float) -> (Float, Float) {
        let split1 = mb3Split1.process(left: left, right: right)
        let lowBandL = split1.0.0
        let lowBandR = split1.1.0
        let highResidL = split1.0.1
        let highResidR = split1.1.1

        let split2 = mb3Split2.process(left: highResidL, right: highResidR)
        let midBandL = split2.0.0
        let midBandR = split2.1.0
        let highBandL = split2.0.1
        let highBandR = split2.1.1

        let lowOut = compressStereoBand(
            left: lowBandL,
            right: lowBandR,
            leftComp: &mbLowCompL,
            rightComp: &mbLowCompR
        )
        let midOut = compressStereoBand(
            left: midBandL,
            right: midBandR,
            leftComp: &mbMidCompL,
            rightComp: &mbMidCompR
        )
        let highOut = compressStereoBand(
            left: highBandL,
            right: highBandR,
            leftComp: &mbHighCompL,
            rightComp: &mbHighCompR
        )

        return Self.sumStereoBands(
            lowOut,
            midOut,
            highOut,
            makeup: multibandMakeup
        )
    }

    private func processFiveBandMultiband(left: Float, right: Float) -> (Float, Float) {
        let split1 = mb5Split1.process(left: left, right: right)
        let b1L = split1.0.0
        let b1R = split1.1.0
        let rem1L = split1.0.1
        let rem1R = split1.1.1

        let split2 = mb5Split2.process(left: rem1L, right: rem1R)
        let b2L = split2.0.0
        let b2R = split2.1.0
        let rem2L = split2.0.1
        let rem2R = split2.1.1

        let split3 = mb5Split3.process(left: rem2L, right: rem2R)
        let b3L = split3.0.0
        let b3R = split3.1.0
        let rem3L = split3.0.1
        let rem3R = split3.1.1

        let split4 = mb5Split4.process(left: rem3L, right: rem3R)
        let b4L = split4.0.0
        let b4R = split4.1.0
        let b5L = split4.0.1
        let b5R = split4.1.1

        let o1 = compressStereoBand(
            left: b1L, right: b1R, leftComp: &mb5Comp1L, rightComp: &mb5Comp1R)
        let o2 = compressStereoBand(
            left: b2L, right: b2R, leftComp: &mb5Comp2L, rightComp: &mb5Comp2R)
        let o3 = compressStereoBand(
            left: b3L, right: b3R, leftComp: &mb5Comp3L, rightComp: &mb5Comp3R)
        let o4 = compressStereoBand(
            left: b4L, right: b4R, leftComp: &mb5Comp4L, rightComp: &mb5Comp4R)
        let o5 = compressStereoBand(
            left: b5L, right: b5R, leftComp: &mb5Comp5L, rightComp: &mb5Comp5R)

        return Self.sumStereoBands(
            o1,
            o2,
            o3,
            o4,
            o5,
            makeup: multibandMakeup
        )
    }

    private func compressStereoBand(
        left: Float,
        right: Float,
        leftComp: inout MonoCompressor,
        rightComp: inout MonoCompressor
    ) -> (Float, Float) {
        let absL = fabsf(left)
        let absR = fabsf(right)
        if multibandLinkStrength > 1e-4 {
            // When link is enabled, drive both channels from one shared detector.
            // This keeps gain reduction matched between L/R and prevents slow image collapse.
            let sidechain = Self.makeLinkedBandSidechain(
                absLeft: absL,
                absRight: absR,
                linkStrength: multibandLinkStrength
            )
            return (
                leftComp.process(left, sidechainAbs: sidechain),
                rightComp.process(right, sidechainAbs: sidechain)
            )
        }
        return (leftComp.process(left), rightComp.process(right))
    }

    @inline(__always)
    private static func sumStereoBands(
        _ a: (Float, Float),
        _ b: (Float, Float),
        _ c: (Float, Float),
        makeup: Float
    ) -> (Float, Float) {
        ((a.0 + b.0 + c.0) * makeup, (a.1 + b.1 + c.1) * makeup)
    }

    @inline(__always)
    private static func sumStereoBands(
        _ a: (Float, Float),
        _ b: (Float, Float),
        _ c: (Float, Float),
        _ d: (Float, Float),
        _ e: (Float, Float),
        makeup: Float
    ) -> (Float, Float) {
        ((a.0 + b.0 + c.0 + d.0 + e.0) * makeup, (a.1 + b.1 + c.1 + d.1 + e.1) * makeup)
    }

    @inline(__always)
    private static func makeLinkedBandSidechain(
        absLeft: Float,
        absRight: Float,
        linkStrength: Float
    ) -> Float {
        let avgAbs = (absLeft + absRight) * 0.5
        let linkedRMS = sqrtf(((absLeft * absLeft) + (absRight * absRight)) * 0.5)
        return lerpf(avgAbs, linkedRMS, linkStrength)
    }

    static func softClipSafety(_ x: Float, threshold: Float) -> Float {
        let thr = clampf(threshold, 0.5, 0.999)
        let ax = fabsf(x)
        if ax <= thr {
            return x
        }
        let margin = clampf(0.08 * (1.0 - thr), 0.004, 0.03)
        let outMax = min(1.0, thr + margin)
        let knee = max(1e-4, margin * 0.85)
        let clipped = thr + ((outMax - thr) * tanhf((ax - thr) / knee))
        return copysignf(clipped, x)
    }
}
