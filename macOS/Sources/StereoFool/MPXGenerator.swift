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

struct SineCosOsc {
    var s: Float = 0.0
    var c: Float = 1.0
    var phase: Float = 0.0
    var sinInc: Float = 0.0
    var cosInc: Float = 1.0

    init() {}

    mutating func configure(freq: Float, sampleRate: Float) {
        let w = twoPi * freq / sampleRate
        sinInc = sinf(w)
        cosInc = cosf(w)
    }

    @inline(__always) mutating func step() {
        let ns = s * cosInc + c * sinInc
        let nc = c * cosInc - s * sinInc
        s = ns
        c = nc
        phase += sinInc
        if phase >= twoPi { phase -= twoPi }
        if phase < 0 { phase += twoPi }
    }

    @inline(__always) mutating func sin2x() -> Float {
        return 2.0 * s * c
    }
}

struct CompositeTruePeakLimiter {
    var threshold: Float = 0.98
    var releaseMS: Float = 80.0

    private var gain: Float = 1.0
    private var releaseCoeff: Float = 0.0
    private var prevIn: Float = 0.0
    private var initialized: Bool = false

    mutating func configure(sampleRate: Float) {
        let sr = max(8_000.0, sampleRate)
        let relS = max(0.005, Double(releaseMS) * 0.001)
        releaseCoeff = expf(-1.0 / Float(relS * Double(sr)))
        gain = 1.0
        prevIn = 0.0
        initialized = false
        threshold = clampf(threshold, 0.5, 0.999)
    }

    mutating func process(_ x: Float) -> Float {
        if !initialized {
            initialized = true
            prevIn = x
            return clampToThreshold(x)
        }

        let mid = 0.5 * (prevIn + x)

        let p0 = fabsf(mid)
        let p1 = fabsf(x)
        let peak = max(p0, p1)

        var targetGain: Float = 1.0
        if peak > threshold {
            targetGain = threshold / max(1e-9, peak)
        }

        if targetGain < gain {
            gain = targetGain
        } else {
            gain = (releaseCoeff * gain) + ((1.0 - releaseCoeff) * 1.0)
        }

        prevIn = x
        let y = x * gain
        return clampToThreshold(y)
    }

    @inline(__always)
    private func clampToThreshold(_ x: Float) -> Float {
        if fabsf(x) <= threshold { return x }
        return copysignf(threshold, x)
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
    var left1 = OnePoleLP()
    var left2 = OnePoleLP()
    var right1 = OnePoleLP()
    var right2 = OnePoleLP()

    mutating func configure(cutoffHz: Float, sampleRate: Float) {
        left1.configure(cutoffHz: cutoffHz, sampleRate: sampleRate)
        left2.configure(cutoffHz: cutoffHz, sampleRate: sampleRate)
        right1.configure(cutoffHz: cutoffHz, sampleRate: sampleRate)
        right2.configure(cutoffHz: cutoffHz, sampleRate: sampleRate)
        left1.state = 0.0
        left2.state = 0.0
        right1.state = 0.0
        right2.state = 0.0
    }

    mutating func process(left: Float, right: Float) -> (Float, Float) {
        let l = left2.process(left1.process(left))
        let r = right2.process(right1.process(right))
        return (l, r)
    }
}

struct PreemphasisFilter {
    var enabled: Bool = false
    var lpAlpha: Float = 1.0
    var shelfGain: Float = 0.0
    var lpState: Float = 0.0

    mutating func configure(tauUS: Int, sampleRate: Float) {
        guard tauUS > 0 else {
            enabled = false
            lpAlpha = 1.0
            shelfGain = 0.0
            lpState = 0.0
            return
        }
        enabled = true
        let tau = max(1e-6, Float(tauUS) * 1e-6)
        let fc = 1.0 / (twoPi * tau)
        let pole = expf(-twoPi * fc / max(8_000.0, sampleRate))
        lpAlpha = clampf(1.0 - pole, 0.0, 1.0)
        let wRef = twoPi * 15_000.0 * tau
        let refGain = sqrtf(1.0 + (wRef * wRef))
        shelfGain = max(0.0, refGain - 1.0)
    }

    mutating func process(_ x: Float) -> Float {
        guard enabled else { return x }
        lpState += lpAlpha * (x - lpState)
        let hp = x - lpState
        return x + (hp * shelfGain)
    }
}

struct DeemphasisFilter {
    var enabled: Bool = false
    var alpha: Float = 1.0
    var state: Float = 0.0

    mutating func configure(tauUS: Int, sampleRate: Float) {
        guard tauUS > 0 else {
            enabled = false
            alpha = 1.0
            state = 0.0
            return
        }
        enabled = true
        let tau = max(1e-6, Float(tauUS) * 1e-6)
        let sr = max(8_000.0, sampleRate)
        alpha = clampf(1.0 - expf(-1.0 / (tau * sr)), 0.0, 1.0)
        state = 0.0
    }

    mutating func process(_ x: Float) -> Float {
        guard enabled else { return x }
        state += alpha * (x - state)
        return state
    }
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
        return value
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
    private let rtFrames: [String]
    private let psSequence: [TimedTextFrame]
    private let rtSequence: [TimedTextFrame]
    private let ptynEnabled: Bool
    private let ptynCentered: Bool
    private let ptynFrames: [String]
    private let ptynSequence: [TimedTextFrame]
    private let lpsEnabled: Bool
    private let lpsCentered: Bool
    private let lpsCR: Bool
    private let lpsFrames: [String]
    private let lpsSequence: [TimedTextFrame]
    private let rtPlusEnabled: Bool
    private let rtPlusFormatA: String
    private let rtPlusFormatB: String
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

    private var biphaseKernel: [Float] = []
    private var gaussianKernel: [Float] = []
    private var shapingKernel: [Float] = []
    private var biphaseOverlapAdd: [Float] = []
    private var biphaseOverlapIndex: Int = 0
    private var shapingPeak: Float = 1.0

    init(config: AppConfig, sampleRate: Float) {
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
        self.ptynSequence = Self.parseTimedSequence(
            config.rdsPTYN, width: 8, uppercase: true, center: ptynCentered)
        self.lpsEnabled = config.rdsEnableLPS
        self.lpsCentered = config.rdsLPSCentered
        self.lpsCR = config.rdsLPSCR
        self.lpsFrames = Self.parseTimedFrames(
            config.rdsLongPS32, width: 32, uppercase: false, center: lpsCentered)
        self.lpsSequence = Self.parseTimedSequence(
            config.rdsLongPS32, width: 32, uppercase: false, center: lpsCentered)
        self.rtPlusEnabled = config.rdsEnableRTPlus
        self.rtPlusFormatA = config.rdsRTPlusFormatA
        self.rtPlusFormatB = config.rdsRTPlusFormatB
        self.enCT = config.rdsEnableCT
        self.enID = config.rdsEnableID
        self.eccCode = Self.parseHexByte(config.rdsECC)
        self.licCode = Self.parseHexByte(config.rdsLIC)
        self.tzOffset = config.rdsTZOffset
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
        let frame = psSequence.isEmpty ? psFrames[psFrameIndex] : psSequence[psSeqIndex].text
        let bytes = Array(frame.utf8)
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
        let frame = currentRTFrame(limit: limit)
        let bytes = Array(frame.utf8)
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
            let selectedFormat = (abFlag == 0) ? rtPlusFormatA : rtPlusFormatB
            refreshRTPlusTagsIfNeeded(text: frame, format: selectedFormat)
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
        let frame =
            ptynSequence.isEmpty ? ptynFrames[ptynFrameIndex] : ptynSequence[ptynSeqIndex].text
        let bytes = Array(frame.utf8)
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
        let frame = lpsSequence.isEmpty ? lpsFrames[lpsFrameIndex] : lpsSequence[lpsSeqIndex].text
        let prepared = lpsCR ? Self.prepareCRFrame(frame, width: 32) : frame
        let bytes = Array(prepared.utf8)
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
        let calendar = Calendar(identifier: .gregorian)
        let comps = calendar.dateComponents(
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
        let calendar = Calendar(identifier: .gregorian)
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
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

    private func currentRTFrame(limit: Int) -> String {
        if rtManualBuffers {
            let buf = currentManualRTBuffer()
            if buf != lastManualRTBuffer {
                rtSegment = 0
                lastManualRTBuffer = buf
            }
            let raw = buf == 0 ? rtBufferA : rtBufferB
            return Self.prepareRTFrame(raw, width: limit, centered: rtCentered, appendCR: rtCR)
        }

        guard !rtSequence.isEmpty else {
            return Self.prepareRTFrame(
                rtFrames[rtFrameIndex], width: limit, centered: rtCentered, appendCR: rtCR)
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
        return Self.prepareRTFrame(frame, width: limit, centered: rtCentered, appendCR: rtCR)
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

    private func refreshRTPlusTagsIfNeeded(text: String, format: String) {
        let signature = text + "|" + format
        if signature == rtPlusSignature {
            return
        }
        rtPlusSignature = signature
        rtPlusToggle ^= 1
        rtPlusTags = Self.parseRTPlusTags(text: text, format: format)
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

    private static let ebuLatinMap: [UInt32: String] = [
        0x00E9: "e", 0x00E8: "e", 0x00EA: "e", 0x00EB: "e",
        0x00E1: "a", 0x00E0: "a", 0x00E2: "a", 0x00E4: "a", 0x00E5: "a",
        0x00ED: "i", 0x00EC: "i", 0x00EE: "i", 0x00EF: "i",
        0x00F3: "o", 0x00F2: "o", 0x00F4: "o", 0x00F6: "o",
        0x00FA: "u", 0x00F9: "u", 0x00FB: "u", 0x00FC: "u",
        0x00E7: "c", 0x00F1: "n", 0x00DF: "ss",
        0x20AC: "E", 0x00E6: "ae", 0x0153: "oe",
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
            return cleanMarkerSpaces(convertToEBULatin(loaded)).uppercased()
        }
        resolved = replaceMarkers(in: resolved, pattern: #"\\r\"([^\"]+)\""#) { path in
            guard let loaded = loadTextFromFile(path) else {
                failed = true
                return ""
            }
            return cleanMarkerSpaces(convertToEBULatin(loaded))
        }
        resolved = replaceMarkers(in: resolved, pattern: #"\\w\"([^\"]+)\""#) { source in
            guard let loaded = loadTextFromURL(source) else {
                failed = true
                return ""
            }
            return cleanMarkerSpaces(convertToEBULatin(loaded))
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

    private static func convertToEBULatin(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            if scalar.value <= 0x7F {
                out.append(Character(scalar))
            } else if let mapped = ebuLatinMap[scalar.value] {
                out += mapped
            } else {
                out += "?"
            }
        }
        return out
    }

    private static func sanitizeText(_ raw: String, uppercase: Bool) -> String {
        let folded = raw.folding(
            options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
        let mapped = folded.unicodeScalars.map { scalar -> Character in
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

    private static func parseRTPlusTags(text: String, format: String) -> [RTPlusTag] {
        if text.isEmpty || format.isEmpty {
            return []
        }

        var escaped = NSRegularExpression.escapedPattern(for: format)
        escaped = escaped.replacingOccurrences(of: "\\{artist\\}", with: "(?<artist>.+?)")
        escaped = escaped.replacingOccurrences(of: "\\{title\\}", with: "(?<title>.+?)")
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
        if let artistTag = makeTag(name: "artist", contentType: 4) {
            tags.append(artistTag)
        }
        return tags
    }
}

final class MPXGenerator {
    private var sampleRate: Float
    private let preemphasisUS: Int
    private let toneFreq: Float
    private let toneMode: String
    private let monoMode: Bool
    private let processingBypass: Bool
    private let pilotLevel: Float
    private let sumLevel: Float
    private let diffLevel: Float
    private let inputGain: Float
    private let outputGain: Float
    private let limitEnabled: Bool
    private let threshold: Float
    private let deviationScale: Float
    private let programLowpassHz: Float

    private let widebandAGCEnabled: Bool
    private let widebandAGCTargetDB: Float
    private let widebandAGCMaxGain: Float
    private let widebandAGCMinGain: Float
    private let widebandAGCAttackMS: Float
    private let widebandAGCReleaseMS: Float
    private var widebandAGCEnv = EnvelopeFollower()

    private let hpfHz: Float
    private let hfTrimDB: Float
    private let hfTrimHz: Float
    private var inputHPF = StereoBiquad()
    private var hfTrim = StereoBiquad()

    private let limitLookaheadEnabled: Bool
    private let limitLookaheadMS: Float
    private var lookaheadLimiter = LookaheadLimiter()

    private let orbassEnabled: Bool
    private let orbassAmount: Float
    private let orbassHarmonics: Float
    private let orbassDrive: Float
    private let orbassDensity: Float
    private let orbassSubharmonicsEnabled: Bool
    private let orbassSubharmonicsAmount: Float
    private let orbassFreqHz: Float
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

    private let multibandEnabled: Bool
    private let multibandMode: Int
    private let multibandMakeup: Float
    private let multibandKneeDB: Float
    private let multibandLinkStrength: Float
    private let multibandReleaseProgramDependent: Bool
    private let multibandX1Hz: Float
    private let multibandX2Hz: Float
    private let multibandX3Hz: Float
    private let multibandX4Hz: Float
    private let multibandLowThresholdDB: Float
    private let multibandMidThresholdDB: Float
    private let multibandHighThresholdDB: Float
    private let multibandLowRatio: Float
    private let multibandMidRatio: Float
    private let multibandHighRatio: Float
    private let multibandLowAttackMS: Float
    private let multibandMidAttackMS: Float
    private let multibandHighAttackMS: Float
    private let multibandLowReleaseMS: Float
    private let multibandMidReleaseMS: Float
    private let multibandHighReleaseMS: Float

    private var mbLowL = OnePoleLP()
    private var mbLowR = OnePoleLP()
    private var mbMidL = OnePoleLP()
    private var mbMidR = OnePoleLP()
    private var mbLowCompL = MonoCompressor()
    private var mbLowCompR = MonoCompressor()
    private var mbMidCompL = MonoCompressor()
    private var mbMidCompR = MonoCompressor()
    private var mbHighCompL = MonoCompressor()
    private var mbHighCompR = MonoCompressor()

    private var mb5X1L = OnePoleLP()
    private var mb5X1R = OnePoleLP()
    private var mb5X2L = OnePoleLP()
    private var mb5X2R = OnePoleLP()
    private var mb5X3L = OnePoleLP()
    private var mb5X3R = OnePoleLP()
    private var mb5X4L = OnePoleLP()
    private var mb5X4R = OnePoleLP()
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

    private let stereoWidenEnabled: Bool
    private let widenWidth: Float
    private let widenCenter: Float
    private let widenMix: Float
    private var rdsCoder: BasicRDSCoder?

    private let compositeLimiterEnabled: Bool
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
    private var monitorNoiseGateGain: Float = 0.0
    private var monitorNoiseGateOpen: Bool = false
    private var lastProgramActivity: Float = 0.0
    private var monitorProgramEnv: Float = 0.0
    private var monitorProgramNoiseFloor: Float = 0.0
    private var monitorExpectedSideEnv: Float = 0.0
    private var monitorExpectedSideAttackCoeff: Float = 0.0
    private var monitorExpectedSideReleaseCoeff: Float = 0.0
    private var monitorCollapseHoldSamples: Int = 0
    private var monitorCollapseCooldownSamples: Int = 0

    init(config: AppConfig, sampleRate: Double) {
        self.sampleRate = Float(max(8_000.0, sampleRate))
        self.preemphasisUS = config.preemphasisUS
        self.toneFreq = Float(config.testToneFreq)
        self.toneMode = config.testToneMode.lowercased()
        self.monoMode = config.monoMode
        self.processingBypass = config.processingBypass
        self.pilotLevel = Float(config.pilotLevel)
        self.sumLevel = Float(config.sumLevel)
        self.diffLevel = Float(config.diffLevel)
        self.inputGain = powf(10.0, Float(config.inputGainDB) / 20.0)
        self.outputGain = powf(10.0, Float(config.outputGainDB) / 20.0)
        self.limitEnabled = config.limitMPX
        self.threshold = clampf(Float(config.limitThreshold), 0.5, 0.999)
        self.deviationScale = Float(config.mpxDeviationKHz / 75.0)
        self.programLowpassHz = Float(config.programLowpassHz)

        self.widebandAGCEnabled = config.widebandAGCEnabled
        self.widebandAGCTargetDB = Float(config.widebandAGCTargetDB)
        self.widebandAGCMaxGain = powf(10.0, Float(config.widebandAGCMaxGainDB) / 20.0)
        self.widebandAGCMinGain = powf(10.0, Float(config.widebandAGCMinGainDB) / 20.0)
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
        self.widenWidth = clampf(Float(config.stereoWidenWidth), 0.0, 1.0)
        self.widenCenter = clampf(Float(config.stereoWidenCenter), 0.0, 1.0)
        self.widenMix = clampf(Float(config.stereoWidenMix), 0.0, 1.0)
        self.rdsCoder = BasicRDSCoder(config: config, sampleRate: self.sampleRate)

        self.toneStep = 0.0

        preSum.configure(tauUS: preemphasisUS, sampleRate: self.sampleRate)
        preDiff.configure(tauUS: preemphasisUS, sampleRate: self.sampleRate)
        programLP.configure(cutoffHz: programLowpassHz, sampleRate: self.sampleRate)

        widebandAGCEnv.configure(
            sampleRate: self.sampleRate,
            attackMS: widebandAGCAttackMS,
            releaseMS: widebandAGCReleaseMS
        )
        inputHPF.configureHighpass(cutoffHz: hpfHz, sampleRate: self.sampleRate)
        hfTrim.configureHighShelf(gainDB: hfTrimDB, cutoffHz: hfTrimHz, sampleRate: self.sampleRate)
        configureOrbassFilters()
        configureMultibandFilters()
        configureMultibandCompressors()
        lookaheadLimiter.configure(
            sampleRate: self.sampleRate,
            lookaheadMS: limitLookaheadMS,
            threshold: threshold,
            enabled: limitEnabled && limitLookaheadEnabled
        )
        compositeLimiter.configure(sampleRate: self.sampleRate)
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
        programLP.configure(cutoffHz: programLowpassHz, sampleRate: sampleRate)
        widebandAGCEnv.configure(
            sampleRate: sampleRate, attackMS: widebandAGCAttackMS, releaseMS: widebandAGCReleaseMS)
        inputHPF.configureHighpass(cutoffHz: hpfHz, sampleRate: sampleRate)
        hfTrim.configureHighShelf(gainDB: hfTrimDB, cutoffHz: hfTrimHz, sampleRate: sampleRate)
        configureOrbassFilters()
        configureMultibandFilters()
        configureMultibandCompressors()
        lookaheadLimiter.configure(
            sampleRate: sampleRate,
            lookaheadMS: limitLookaheadMS,
            threshold: threshold,
            enabled: limitEnabled && limitLookaheadEnabled
        )
        compositeLimiter.configure(sampleRate: sampleRate)
        rdsCoder?.setSampleRate(sampleRate)
        updateDerivedRates()
        configureMonitorDemod()
    }

    var isProcessingBypassEnabled: Bool {
        processingBypass
    }

    private func updateDerivedRates() {
        toneStep = twoPi * toneFreq / sampleRate
        pilotOsc.configure(freq: pilotFreq, sampleRate: sampleRate)

        let nyquist = (sampleRate * 0.5) - 100.0
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

        mbLowL.configure(cutoffHz: x1, sampleRate: sampleRate)
        mbLowR.configure(cutoffHz: x1, sampleRate: sampleRate)
        mbMidL.configure(cutoffHz: x2, sampleRate: sampleRate)
        mbMidR.configure(cutoffHz: x2, sampleRate: sampleRate)

        mb5X1L.configure(cutoffHz: x1, sampleRate: sampleRate)
        mb5X1R.configure(cutoffHz: x1, sampleRate: sampleRate)
        mb5X2L.configure(cutoffHz: x2, sampleRate: sampleRate)
        mb5X2R.configure(cutoffHz: x2, sampleRate: sampleRate)
        mb5X3L.configure(cutoffHz: x3, sampleRate: sampleRate)
        mb5X3R.configure(cutoffHz: x3, sampleRate: sampleRate)
        mb5X4L.configure(cutoffHz: x4, sampleRate: sampleRate)
        mb5X4R.configure(cutoffHz: x4, sampleRate: sampleRate)
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
            l = clampf(l * outputGain, -1.0, 1.0)
            r = clampf(r * outputGain, -1.0, 1.0)
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
            left[i] = clampf(l * inputGain * outputGain, -1.0, 1.0)
            right[i] = clampf(r * inputGain * outputGain, -1.0, 1.0)
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
        var l = leftIn * inputGain
        var r = rightIn * inputGain

        if monoMode {
            let m = (l + r) * 0.5
            l = m
            r = m
        }
        let inputActivity = max(fabsf(l), fabsf(r))

        if !processingBypass {
            if widebandAGCEnabled {
                let mono = (fabsf(l) + fabsf(r)) * 0.5
                let env = max(1e-7, widebandAGCEnv.processAbs(mono))
                let envDB = 20.0 * log10f(env)
                let targetGain = powf(10.0, (widebandAGCTargetDB - envDB) / 20.0)
                let gain = clampf(targetGain, widebandAGCMinGain, widebandAGCMaxGain)
                l *= gain
                r *= gain
            }

            let hpfOut = inputHPF.process(left: l, right: r)
            l = hpfOut.0
            r = hpfOut.1
        }

        let filtered = programLP.process(left: l, right: r)
        l = filtered.0
        r = filtered.1
        let stereoRefL = l
        let stereoRefR = r

        if !processingBypass {
            let trimmed = hfTrim.process(left: l, right: r)
            l = trimmed.0
            r = trimmed.1

            if orbassEnabled {
                let orbassOut = processOrbass(left: l, right: r)
                l = orbassOut.0
                r = orbassOut.1
            }

            if multibandEnabled {
                let mbOut = processMultibandStereo(left: l, right: r)
                l = mbOut.0
                r = mbOut.1
            }

            if stereoWidenEnabled {
                let mid = (l + r) * 0.5
                let side = (l - r) * 0.5
                let sideGain = widenWidth * 2.0
                let midGain = widenCenter * 2.0
                let wetL = (mid * midGain) + (side * sideGain)
                let wetR = (mid * midGain) - (side * sideGain)
                l = lerpf(l, wetL, widenMix)
                r = lerpf(r, wetR, widenMix)
            }
        }

        if !processingBypass {
            let protected = protectStereoImage(
                inputL: stereoRefL,
                inputR: stereoRefR,
                outputL: l,
                outputR: r
            )
            l = protected.0
            r = protected.1
        }

        let postSideAbs = fabsf((l - r) * 0.5)
        let sideCoeff =
            postSideAbs > monitorExpectedSideEnv
            ? monitorExpectedSideAttackCoeff
            : monitorExpectedSideReleaseCoeff
        monitorExpectedSideEnv =
            (sideCoeff * monitorExpectedSideEnv) + ((1.0 - sideCoeff) * postSideAbs)

        var base = ((l + r) * 0.5) * sumLevel
        var diff = monoMode ? 0.0 : (((r - l) * 0.5) * diffLevel)

        base = preSum.process(base)
        diff = preDiff.process(diff)
        lastProgramActivity = inputActivity

        tonePhase += toneStep
        if tonePhase >= twoPi { tonePhase -= twoPi }

        pilotOsc.step()
        pilotPhaseForRDS = pilotOsc.phase
        let pilot = pilotSupported ? (pilotOsc.s * pilotLevel) : 0.0
        let sub = stereoSubcarrierSupported ? pilotOsc.sin2x() : 0.0
        lastSubcarrierSample = sub

        rdsCoder?.updateRDSPilotPhase(pilotPhaseForRDS)
        let rds = rdsSupported ? (rdsCoder?.nextSampleWithPilotLock() ?? 0.0) : 0.0
        
        var mpx = (base + (diff * sub) + pilot + rds) * deviationScale

        if compositeLimiterEnabled {
            mpx = compositeLimiter.process(mpx)
        }

        mpx *= outputGain
        mpx = clampf(mpx, -1.0, 1.0)

        return mpx
    }

    private func protectStereoImage(
        inputL: Float,
        inputR: Float,
        outputL: Float,
        outputR: Float
    ) -> (Float, Float) {
        // TEMPORARILY DISABLED: The accumulated stereoProtectGain was causing
        // gradual stereo narrowing over 40-60 seconds. Disabling to verify
        // if this is the root cause.
        return (outputL, outputR)
    }

    private func resetDynamicStereoState() {
        widebandAGCEnv.value = 0.0

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
        let lowRatio = fabsf(low) / midAbs
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

        let driveFactor = 0.75 + (0.75 * drive)
        let densityFactor = 0.62 + (0.95 * density)
        let boostGain = amount * driveFactor * densityFactor * (0.70 + (0.90 * adaptive))
        let lowBoost = low * boostGain

        let nlDrive = 1.0 + (drive * (1.6 + (amount * 3.2) + (harmonics * 2.8)))
        let harmonicSrc = tanhf(low * nlDrive) - tanhf(low * (0.45 + (0.25 * density)))
        let harmonicBand = orbassHarmLPF.process(orbassHarmHPF.process(harmonicSrc))
        let harmonicGain = harmonics * (0.55 + (0.95 * density)) * (0.75 + (0.85 * adaptive))
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
            let subGain = subAmount * (0.45 + (0.75 * density)) * (0.70 + (0.45 * drive))
            enhancement += subWave * subGain
        }

        let enhClip = max(0.62, 0.86 - (0.12 * density))
        let satEnhancement = enhClip * tanhf(enhancement / max(1e-4, enhClip))
        var midOut = mid + satEnhancement
        midOut *= 1.0 / (1.0 + (0.05 * amount) + (0.04 * subAmount))

        let outMidAbs = max(1e-6, fabsf(midOut))
        let targetMakeupPower = 0.62 + (0.12 * density)
        let targetMakeup = clampf(
            powf(midAbs / outMidAbs, targetMakeupPower),
            0.90,
            1.26 + (0.14 * density)
        )
        orbassMakeupGain = smoothOrbassGain(
            current: orbassMakeupGain,
            target: targetMakeup,
            attackMS: 35.0,
            releaseMS: 180.0
        )
        midOut *= orbassMakeupGain

        var outL = midOut + side
        var outR = midOut - side
        let inPeak = max(max(fabsf(left), fabsf(right)), 1e-6)
        let outPeak = max(max(fabsf(outL), fabsf(outR)), 1e-6)
        let allowedPeak = inPeak * (1.10 + (0.06 * amount) + (0.08 * subAmount))
        if outPeak > allowedPeak {
            let scale = allowedPeak / outPeak
            outL = left + ((outL - left) * scale)
            outR = right + ((outR - right) * scale)
        }
        return (outL, outR)
    }

    private func smoothOrbassGain(current: Float, target: Float, attackMS: Float, releaseMS: Float)
        -> Float
    {
        let sr = max(8_000.0, sampleRate)
        let tauMS = target > current ? max(0.1, attackMS) : max(1.0, releaseMS)
        let coeff = expf(-1.0 / ((tauMS * 0.001) * sr))
        return (coeff * current) + ((1.0 - coeff) * target)
    }

    private func processMultibandStereo(left: Float, right: Float) -> (Float, Float) {
        if multibandMode == 5 {
            return processFiveBandMultiband(left: left, right: right)
        }
        return processThreeBandMultiband(left: left, right: right)
    }

    private func processThreeBandMultiband(left: Float, right: Float) -> (Float, Float) {
        let lowBandL = mbLowL.process(left)
        let lowBandR = mbLowR.process(right)
        let lowCutL = left - lowBandL
        let lowCutR = right - lowBandR
        let midBandL = mbMidL.process(lowCutL)
        let midBandR = mbMidR.process(lowCutR)
        let highBandL = lowCutL - midBandL
        let highBandR = lowCutR - midBandR

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

        let outL = (lowOut.0 + midOut.0 + highOut.0) * multibandMakeup
        let outR = (lowOut.1 + midOut.1 + highOut.1) * multibandMakeup
        return (outL, outR)
    }

    private func processFiveBandMultiband(left: Float, right: Float) -> (Float, Float) {
        let b1L = mb5X1L.process(left)
        let b1R = mb5X1R.process(right)
        let rem1L = left - b1L
        let rem1R = right - b1R

        let b2L = mb5X2L.process(rem1L)
        let b2R = mb5X2R.process(rem1R)
        let rem2L = rem1L - b2L
        let rem2R = rem1R - b2R

        let b3L = mb5X3L.process(rem2L)
        let b3R = mb5X3R.process(rem2R)
        let rem3L = rem2L - b3L
        let rem3R = rem2R - b3R

        let b4L = mb5X4L.process(rem3L)
        let b4R = mb5X4R.process(rem3R)
        let b5L = rem3L - b4L
        let b5R = rem3R - b4R

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

        let outL = (o1.0 + o2.0 + o3.0 + o4.0 + o5.0) * multibandMakeup
        let outR = (o1.1 + o2.1 + o3.1 + o4.1 + o5.1) * multibandMakeup
        return (outL, outR)
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
            let avgAbs = (absL + absR) * 0.5
            let linkedRMS = sqrtf(((absL * absL) + (absR * absR)) * 0.5)
            let sidechain = lerpf(avgAbs, linkedRMS, multibandLinkStrength)
            return (
                leftComp.process(left, sidechainAbs: sidechain),
                rightComp.process(right, sidechainAbs: sidechain)
            )
        }
        return (leftComp.process(left), rightComp.process(right))
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
