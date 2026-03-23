import Foundation

private struct VerificationMetrics {
    var sampleCount: Int = 0
    var peakAbs: Float = 0.0
    var sumSquares: Double = 0.0
    var maxLimiterGRDB: Float = 0.0
    var maxSafetyGRDB: Float = 0.0
    var maxAudioCompositePeak: Float = 0.0
    var minBudgetMarginDB: Float = .greatestFiniteMagnitude
    var pilotPercent: Float = 0.0
    var rdsPercent: Float = 0.0
    var maxAGCReductionDB: Float = 0.0
    var detectorDBAtMaxReduction: Float = -120.0

    mutating func ingest(
        sample: Float,
        agc: MPXGenerator.AGCStatus,
        limiter: MPXGenerator.FinalLimiterStatus,
        calibration: MPXGenerator.CompositeCalibrationStatus
    ) {
        sampleCount += 1
        let absSample = fabsf(sample)
        peakAbs = max(peakAbs, absSample)
        sumSquares += Double(sample * sample)
        maxLimiterGRDB = max(maxLimiterGRDB, limiter.gainReductionDB)
        maxSafetyGRDB = max(maxSafetyGRDB, limiter.safetyGainReductionDB)
        maxAudioCompositePeak = max(maxAudioCompositePeak, calibration.audioPeak)
        minBudgetMarginDB = min(minBudgetMarginDB, calibration.budgetMarginDB)
        pilotPercent = calibration.pilotPercent
        rdsPercent = calibration.rdsPercent
        let reduction = max(0.0, -agc.gainDB)
        if reduction >= maxAGCReductionDB {
            maxAGCReductionDB = reduction
            detectorDBAtMaxReduction = agc.detectorDB
        }
    }

    var rms: Float {
        guard sampleCount > 0 else { return 0.0 }
        return Float(sqrt(sumSquares / Double(sampleCount)))
    }
}

private struct VerificationScenario {
    let name: String
    let description: String
    let sample: (_ frameIndex: Int, _ sampleRate: Double) -> (Float, Float)
}

private struct DeterministicNoise {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> Float {
        state = state &* 6364136223846793005 &+ 1
        let upper = UInt32((state >> 32) & 0xFFFF_FFFF)
        let normalized = Float(upper) / Float(UInt32.max)
        return (normalized * 2.0) - 1.0
    }
}

private func verificationScenarios() -> [VerificationScenario] {
    var programNoiseL = DeterministicNoise(seed: 0x1234_5678_ABCD_EF01)
    var programNoiseR = DeterministicNoise(seed: 0x0FED_CBA9_8765_4321)

    return [
        VerificationScenario(
            name: "mono_1khz",
            description: "Mono 1 kHz sine at moderate level"
        ) { frame, sampleRate in
            let t = Double(frame) / sampleRate
            let tone = Float(sin(2.0 * Double.pi * 1000.0 * t)) * 0.55
            return (tone, tone)
        },
        VerificationScenario(
            name: "stereo_diff_400hz",
            description: "Out-of-phase stereo stress tone"
        ) { frame, sampleRate in
            let t = Double(frame) / sampleRate
            let tone = Float(sin(2.0 * Double.pi * 400.0 * t)) * 0.50
            return (tone, -tone)
        },
        VerificationScenario(
            name: "program_mix",
            description: "Deterministic multitone and noise program-like mix"
        ) { frame, sampleRate in
            let t = Double(frame) / sampleRate
            let envelope =
                0.42
                + (0.18 * (0.5 + 0.5 * sin(2.0 * Double.pi * 0.37 * t)))
                + (0.08 * (0.5 + 0.5 * sin(2.0 * Double.pi * 0.071 * t)))

            let bass = sin(2.0 * Double.pi * 55.0 * t)
            let lowMid = sin(2.0 * Double.pi * 220.0 * t)
            let mid = sin(2.0 * Double.pi * 880.0 * t)
            let high = sin(2.0 * Double.pi * 3200.0 * t)

            let left =
                Float(envelope)
                * Float((0.42 * bass) + (0.24 * lowMid) + (0.16 * mid) + (0.08 * high))
                + (programNoiseL.next() * 0.025)
            let right =
                Float(envelope)
                * Float((0.39 * bass) + (0.21 * lowMid) - (0.12 * mid) + (0.10 * high))
                + (programNoiseR.next() * 0.025)

            return (left, right)
        },
    ]
}

private func verifyScenario(
    config: AppConfig,
    durationSeconds: Double,
    scenario: VerificationScenario
) -> VerificationMetrics {
    let sampleRate = max(8_000.0, config.sampleRate)
    let frames = max(1, Int((durationSeconds * sampleRate).rounded()))
    let generator = MPXGenerator(config: config, sampleRate: sampleRate)
    var metrics = VerificationMetrics()

    for frame in 0..<frames {
        let source = scenario.sample(frame, sampleRate)
        let mpx = generator.renderSingleSample(leftIn: source.0, rightIn: source.1)
        metrics.ingest(
            sample: mpx,
            agc: generator.agcStatus,
            limiter: generator.finalLimiterStatus,
            calibration: generator.compositeCalibrationStatus
        )
    }

    return metrics
}

private func dbfsString(_ linear: Float) -> String {
    guard linear > 1e-9 else { return "-inf" }
    return String(format: "%.2f", 20.0 * log10(Double(linear)))
}

private func deviationString(peakAbs: Float, targetDeviationKHz: Double) -> String {
    String(format: "%.1f", Double(peakAbs) * max(1.0, targetDeviationKHz))
}

private func padded(_ text: String, width: Int) -> String {
    if text.count >= width {
        return String(text.prefix(width))
    }
    return text + String(repeating: " ", count: width - text.count)
}

private func leftPadded(_ text: String, width: Int) -> String {
    if text.count >= width {
        return String(text.suffix(width))
    }
    return String(repeating: " ", count: width - text.count) + text
}

private func nonNegative(_ value: Float) -> Float {
    if value <= 0.0005 {
        return 0.0
    }
    return value
}

func runVerificationHarness(configPath: String, durationSeconds: Double) throws -> Int32 {
    let config = try AppConfig.load(fromINI: configPath)
    let scenarios = verificationScenarios()

    print("StereoFool Verification")
    print("Config: \(configPath)")
    print(
        "Render: \(Int(config.sampleRate)) Hz • Block \(config.blockSize) • Duration \(String(format: "%.1f", durationSeconds)) s"
    )
    print("")
    print(
        "Scenario              Peak dBFS  Dev kHz  LimGR  SafeGR  AudioPk  Pilot  RDS   Margin  AGC"
    )
    print(
        "--------------------  ---------  -------  -----  ------  -------  -----  ----  ------  ----"
    )

    var worstPeak: Float = 0.0
    var worstSafety: Float = 0.0
    var worstMargin: Float = .greatestFiniteMagnitude

    for scenario in scenarios {
        let metrics = verifyScenario(
            config: config,
            durationSeconds: durationSeconds,
            scenario: scenario
        )
        worstPeak = max(worstPeak, metrics.peakAbs)
        worstSafety = max(worstSafety, metrics.maxSafetyGRDB)
        worstMargin = min(worstMargin, metrics.minBudgetMarginDB)

        let line =
            "\(padded(scenario.name, width: 20))  "
            + "\(leftPadded(dbfsString(metrics.peakAbs), width: 9))"
            + "  \(leftPadded(deviationString(peakAbs: metrics.peakAbs, targetDeviationKHz: config.mpxDeviationKHz), width: 7))"
            + "  \(String(format: "%5.1f", nonNegative(metrics.maxLimiterGRDB)))"
            + "  \(String(format: "%6.1f", nonNegative(metrics.maxSafetyGRDB)))"
            + "  \(leftPadded(dbfsString(metrics.maxAudioCompositePeak), width: 7))"
            + "  \(String(format: "%5.1f", metrics.pilotPercent))"
            + "  \(String(format: "%4.1f", metrics.rdsPercent))"
            + "  \(String(format: "%6.1f", metrics.minBudgetMarginDB))"
            + "  \(String(format: "%4.1f", metrics.maxAGCReductionDB))"
        print(line)
    }

    print("")
    print("Assessment")
    print("Worst MPX peak: \(dbfsString(worstPeak)) dBFS")
    print("Worst safety limiter GR: \(String(format: "%.1f", nonNegative(worstSafety))) dB")
    print("Worst composite margin: \(String(format: "%.1f", worstMargin)) dB")

    if worstSafety > 1.0 {
        print("Result: WARN - safety limiter is doing significant work.")
        return 2
    } else if worstMargin < -0.25 {
        print("Result: WARN - composite budget exceeded on at least one scenario.")
        return 2
    } else if worstMargin < 0.0 || worstSafety > 0.25 {
        print("Result: TIGHT - verification stayed close to the composite budget limit.")
        return 1
    } else {
        print("Result: OK - no obvious composite-budget or safety-limiter issue.")
        return 0
    }
}
