import Foundation

struct AppConfig {
    static let appVersion: String = "0.8"

    static var defaultINIPath: String {
        let fileManager = FileManager.default
        if let appSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            return appSupport
                .appendingPathComponent("StereoFool", isDirectory: true)
                .appendingPathComponent("StereoFool.ini", isDirectory: false)
                .path
        }
        return ((NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/StereoFool/StereoFool.ini")
            as NSString)
            .standardizingPath
    }

    var sampleRate: Double = 192_000.0
    var fftWindow96kHz: Bool = true
    var blockSize: Int = 2048
    var sourceMode: String = "input"
    var inputDeviceUID: String?
    var outputDeviceUID: String?
    var monitorDeviceUID: String?
    var monitorEnabled: Bool = false
    var processingBypass: Bool = false
    var testToneMode: String = "mono"
    var testToneFreq: Double = 1000.0
    var pilotLevel: Double = 0.08
    var sumLevel: Double = 1.0
    var diffLevel: Double = 1.0
    var monoMode: Bool = false
    var inputGainDB: Double = 0.0
    var outputGainDB: Double = 0.0
    var preemphasisUS: Int = 50
    var hpfHz: Double = 30.0
    var hfTrimDB: Double = 0.0
    var hfTrimHz: Double = 4000.0
    var programLowpassHz: Double = 16_400.0
    var limitMPX: Bool = true
    var limitThreshold: Double = 0.98
    var limitLookaheadMS: Double = 5.0
    var limitLookaheadEnabled: Bool = true
    var compositeLimiterEnabled: Bool = false
    var mpxDeviationKHz: Double = 75.0
    var enRDS: Bool = true
    var widebandAGCEnabled: Bool = false
    var widebandAGCTargetDB: Double = -18.0
    var widebandAGCAttackMS: Double = 15.0
    var widebandAGCReleaseMS: Double = 220.0
    var widebandAGCMaxGainDB: Double = 10.0
    var widebandAGCMinGainDB: Double = -8.0
    var orbassEnabled: Bool = false
    var orbassAmount: Double = 0.35
    var orbassFreqHz: Double = 95.0
    var orbassHarmonics: Double = 0.35
    var orbassDrive: Double = 1.0
    var orbassDensity: Double = 0.65
    var orbassSubharmonicsEnabled: Bool = false
    var orbassSubharmonicsAmount: Double = 0.35
    var stereoWidenEnabled: Bool = false
    var stereoWidenWidth: Double = 0.5
    var stereoWidenCenter: Double = 0.5
    var stereoWidenMix: Double = 1.0
    var multibandEnabled: Bool = false
    var multibandMode: Int = 3
    var multibandPresetID: String = "3_chr"
    var multibandIntensity: String = "normal"
    var multibandX1Hz: Double = 80.0
    var multibandX2Hz: Double = 320.0
    var multibandX3Hz: Double = 1200.0
    var multibandX4Hz: Double = 5000.0
    var multibandLowHz: Double = 400.0
    var multibandHighHz: Double = 2000.0
    var multibandLowThresholdDB: Double = -22.0
    var multibandMidThresholdDB: Double = -20.0
    var multibandHighThresholdDB: Double = -18.0
    var multibandLowRatio: Double = 2.3
    var multibandMidRatio: Double = 2.0
    var multibandHighRatio: Double = 1.6
    var multibandLowAttackMS: Double = 20.0
    var multibandMidAttackMS: Double = 14.0
    var multibandHighAttackMS: Double = 8.0
    var multibandLowReleaseMS: Double = 320.0
    var multibandMidReleaseMS: Double = 240.0
    var multibandHighReleaseMS: Double = 170.0
    var multibandKneeDB: Double = 2.4
    var multibandLinkStrength: Double = 0.4
    var multibandReleaseProgramDependent: Bool = true
    var multibandMakeupDB: Double = 0.0
    var rdsLevel: Double = 2.0
    var rdsPI: String = "82FF"
    var rdsPTY: Int = 8
    var rdsTP: Bool = false
    var rdsTA: Bool = false
    var rdsMS: Bool = true
    var rdsDI_STEREO: Bool = true
    var rdsDI_HEAD: Bool = false
    var rdsDI_COMP: Bool = true
    var rdsDI_DYN: Bool = false
    var rdsEnableAF: Bool = false
    var rdsAFList: String = "88.1, 98.8, 106.6"
    var rdsAFMethod: String = "A"
    var rdsPSDynamic: String =
        "3s:Stereo- 3s:Fool 3s:MAC 3s:App 3s:FM 3s:MPX 3s:+RDS"
    var rdsPSCentered: Bool = true
    var rdsRTText: String =
        "10s:StereoFool FM MPX Generator/10s:Native macOS Swift App"
    var rdsRTManualBuffers: Bool = false
    var rdsRTCycleAB: Bool = false
    var rdsRTA: String = "StereoFool: FM MPX + RDS Audio Processor"
    var rdsRTB: String = "StereoFool: FM MPX Generator"
    var rdsRTCR: Bool = true
    var rdsRTCentered: Bool = false
    var rdsRTMode: String = "2A"
    var rdsRTCycle: Bool = true
    var rdsRTCycleTime: Double = 5.0
    var rdsRTActiveBuffer: Int = 0
    var rdsRTABCycleCount: Int = 2
    var rdsPTYN: String = "-STEREO-"
    var rdsEnablePTYN: Bool = true
    var rdsPTYNCentered: Bool = false
    var rdsLongPS32: String = "StereoFool Stereo and RDS Coder"
    var rdsEnableLPS: Bool = true
    var rdsLPSCentered: Bool = false
    var rdsLPSCR: Bool = true
    var rdsEnableRTPlus: Bool = false
    var rdsRTPlusFormatA: String = "{artist} - {title}"
    var rdsRTPlusFormatB: String = "{artist} - {title}"
    var rdsECC: String = "E3"
    var rdsLIC: String = "1D"
    var rdsTZOffset: Double = 1.0
    var rdsEnableCT: Bool = true
    var rdsEnableID: Bool = true
    var rdsAutoStart: Bool = false
    var rdsGroupSequence: String = "0A 0A 2A 0A"
    var rdsSchedulerAuto: Bool = true
    var rdsSchedulerStandard: Bool = true
    var rdsSchedulerStandardLPS: Bool = true
    var rdsFreq: Double = 57_000.0
    var rdsGaussianEnabled: Bool = true
    var rdsGaussianBWHZ: Double = 2400.0
    var rdsGaussianTaps: Int = 81

    static func load(fromINI path: String) throws -> AppConfig {
        let resolvedPath = resolveINIPath(path, forWrite: false)
        let parsed = try INIParser.parseFile(resolvedPath)

        let mpx = parsed["MPX"] ?? [:]
        let interfaces = parsed["INTERFACES"] ?? [:]
        let rds = parsed["RDS"] ?? [:]
        var cfg = AppConfig()

        cfg.sourceMode = interfaces.string(
            "source_mode",
            defaultValue: mpx.string("source_mode", defaultValue: cfg.sourceMode)
        )
        cfg.inputDeviceUID = interfaces.optionalString("input_device_uid")
        cfg.outputDeviceUID = interfaces.optionalString("output_device_uid")
        cfg.monitorDeviceUID = interfaces.optionalString("monitor_device_uid")
        cfg.monitorEnabled = interfaces.bool("monitor_enabled", defaultValue: cfg.monitorEnabled)
        cfg.processingBypass = mpx.bool("processing_bypass", defaultValue: cfg.processingBypass)
        cfg.testToneMode = mpx.string("test_tone_mode", defaultValue: cfg.testToneMode)
        cfg.testToneFreq = mpx.double("test_tone_freq", defaultValue: cfg.testToneFreq)
        cfg.pilotLevel = mpx.double("pilot_level", defaultValue: cfg.pilotLevel)
        cfg.sumLevel = mpx.double("sum_level", defaultValue: cfg.sumLevel)
        cfg.diffLevel = mpx.double("diff_level", defaultValue: cfg.diffLevel)
        cfg.monoMode = mpx.bool("mono_mode", defaultValue: cfg.monoMode)
        cfg.inputGainDB = mpx.double("input_gain_db", defaultValue: cfg.inputGainDB)
        cfg.outputGainDB = mpx.double("output_gain_db", defaultValue: cfg.outputGainDB)
        cfg.preemphasisUS = mpx.int("preemphasis_us", defaultValue: cfg.preemphasisUS)
        cfg.hpfHz = mpx.double("hpf_hz", defaultValue: cfg.hpfHz)
        cfg.hfTrimDB = mpx.double("hf_trim_db", defaultValue: cfg.hfTrimDB)
        cfg.hfTrimHz = mpx.double("hf_trim_hz", defaultValue: cfg.hfTrimHz)
        cfg.programLowpassHz = mpx.double("program_lowpass_hz", defaultValue: cfg.programLowpassHz)
        cfg.limitMPX = mpx.bool("limit_mpx", defaultValue: cfg.limitMPX)
        cfg.limitThreshold = mpx.double("limit_threshold", defaultValue: cfg.limitThreshold)
        cfg.limitLookaheadMS = mpx.double("limit_lookahead_ms", defaultValue: cfg.limitLookaheadMS)
        cfg.limitLookaheadEnabled = mpx.bool(
            "limit_lookahead_enabled", defaultValue: cfg.limitLookaheadEnabled)
        cfg.compositeLimiterEnabled = mpx.bool(
            "composite_clipper_enabled", defaultValue: cfg.compositeLimiterEnabled)
        cfg.mpxDeviationKHz = mpx.double("mpx_deviation_khz", defaultValue: cfg.mpxDeviationKHz)
        cfg.enRDS = mpx.bool("en_rds", defaultValue: rds.bool("en_rds", defaultValue: cfg.enRDS))
        cfg.widebandAGCEnabled = mpx.bool(
            "wideband_agc_enabled", defaultValue: cfg.widebandAGCEnabled)
        cfg.widebandAGCTargetDB = mpx.double(
            "wideband_agc_target_db", defaultValue: cfg.widebandAGCTargetDB)
        cfg.widebandAGCAttackMS = mpx.double(
            "wideband_agc_attack_ms", defaultValue: cfg.widebandAGCAttackMS)
        cfg.widebandAGCReleaseMS = mpx.double(
            "wideband_agc_release_ms", defaultValue: cfg.widebandAGCReleaseMS)
        cfg.widebandAGCMaxGainDB = mpx.double(
            "wideband_agc_max_gain_db", defaultValue: cfg.widebandAGCMaxGainDB)
        cfg.widebandAGCMinGainDB = mpx.double(
            "wideband_agc_min_gain_db", defaultValue: cfg.widebandAGCMinGainDB)
        cfg.orbassEnabled = mpx.bool("orbass_enabled", defaultValue: cfg.orbassEnabled)
        cfg.orbassAmount = mpx.double("orbass_amount", defaultValue: cfg.orbassAmount)
        cfg.orbassFreqHz = mpx.double("orbass_freq_hz", defaultValue: cfg.orbassFreqHz)
        cfg.orbassHarmonics = mpx.double("orbass_harmonics", defaultValue: cfg.orbassHarmonics)
        cfg.orbassDrive = mpx.double("orbass_drive", defaultValue: cfg.orbassDrive)
        cfg.orbassDensity = mpx.double("orbass_density", defaultValue: cfg.orbassDensity)
        cfg.orbassSubharmonicsEnabled = mpx.bool(
            "orbass_subharmonics_enabled",
            defaultValue: cfg.orbassSubharmonicsEnabled
        )
        cfg.orbassSubharmonicsAmount = mpx.double(
            "orbass_subharmonics_amount",
            defaultValue: cfg.orbassSubharmonicsAmount
        )
        cfg.stereoWidenEnabled = mpx.bool(
            "stereo_widen_enabled", defaultValue: cfg.stereoWidenEnabled)
        cfg.stereoWidenWidth = mpx.double("stereo_widen_width", defaultValue: cfg.stereoWidenWidth)
        cfg.stereoWidenCenter = mpx.double(
            "stereo_widen_center", defaultValue: cfg.stereoWidenCenter)
        cfg.stereoWidenMix = mpx.double("stereo_widen_mix", defaultValue: cfg.stereoWidenMix)
        cfg.multibandEnabled = mpx.bool("multiband_enabled", defaultValue: cfg.multibandEnabled)
        cfg.multibandMode = mpx.int("multiband_mode", defaultValue: cfg.multibandMode)
        cfg.multibandPresetID = mpx.string("multiband_preset_id", defaultValue: cfg.multibandPresetID)
        cfg.multibandIntensity = mpx.string("multiband_intensity", defaultValue: cfg.multibandIntensity)
        cfg.multibandLowHz = mpx.double("multiband_low_hz", defaultValue: cfg.multibandLowHz)
        cfg.multibandHighHz = mpx.double("multiband_high_hz", defaultValue: cfg.multibandHighHz)
        cfg.multibandX1Hz = mpx.double("multiband_x1_hz", defaultValue: cfg.multibandX1Hz)
        cfg.multibandX2Hz = mpx.double("multiband_x2_hz", defaultValue: cfg.multibandX2Hz)
        cfg.multibandX3Hz = mpx.double("multiband_x3_hz", defaultValue: cfg.multibandX3Hz)
        cfg.multibandX4Hz = mpx.double("multiband_x4_hz", defaultValue: cfg.multibandX4Hz)
        cfg.multibandLowThresholdDB = mpx.double(
            "multiband_low_threshold_db", defaultValue: cfg.multibandLowThresholdDB)
        cfg.multibandMidThresholdDB = mpx.double(
            "multiband_mid_threshold_db", defaultValue: cfg.multibandMidThresholdDB)
        cfg.multibandHighThresholdDB = mpx.double(
            "multiband_high_threshold_db", defaultValue: cfg.multibandHighThresholdDB)
        cfg.multibandLowRatio = mpx.double(
            "multiband_low_ratio", defaultValue: cfg.multibandLowRatio)
        cfg.multibandMidRatio = mpx.double(
            "multiband_mid_ratio", defaultValue: cfg.multibandMidRatio)
        cfg.multibandHighRatio = mpx.double(
            "multiband_high_ratio", defaultValue: cfg.multibandHighRatio)
        cfg.multibandLowAttackMS = mpx.double(
            "multiband_low_attack_ms", defaultValue: cfg.multibandLowAttackMS)
        cfg.multibandMidAttackMS = mpx.double(
            "multiband_mid_attack_ms", defaultValue: cfg.multibandMidAttackMS)
        cfg.multibandHighAttackMS = mpx.double(
            "multiband_high_attack_ms", defaultValue: cfg.multibandHighAttackMS)
        cfg.multibandLowReleaseMS = mpx.double(
            "multiband_low_release_ms", defaultValue: cfg.multibandLowReleaseMS)
        cfg.multibandMidReleaseMS = mpx.double(
            "multiband_mid_release_ms", defaultValue: cfg.multibandMidReleaseMS)
        cfg.multibandHighReleaseMS = mpx.double(
            "multiband_high_release_ms", defaultValue: cfg.multibandHighReleaseMS)
        cfg.multibandKneeDB = mpx.double("multiband_knee_db", defaultValue: cfg.multibandKneeDB)
        cfg.multibandLinkStrength = mpx.double(
            "multiband_link_strength", defaultValue: cfg.multibandLinkStrength)
        cfg.multibandReleaseProgramDependent = mpx.bool(
            "multiband_release_program_dependent",
            defaultValue: cfg.multibandReleaseProgramDependent
        )
        cfg.multibandMakeupDB = mpx.double(
            "multiband_makeup_db", defaultValue: cfg.multibandMakeupDB)
        cfg.rdsLevel = rds.double("rds_level", defaultValue: cfg.rdsLevel)
        cfg.rdsPI = rds.string("pi", defaultValue: cfg.rdsPI)
        cfg.rdsPTY = rds.int("pty", defaultValue: cfg.rdsPTY)
        cfg.rdsTP = rds.bool("tp", defaultValue: cfg.rdsTP)
        cfg.rdsTA = rds.bool("ta", defaultValue: cfg.rdsTA)
        cfg.rdsMS = rds.bool("ms", defaultValue: cfg.rdsMS)
        cfg.rdsDI_STEREO = rds.bool("di_stereo", defaultValue: cfg.rdsDI_STEREO)
        cfg.rdsDI_HEAD = rds.bool("di_head", defaultValue: cfg.rdsDI_HEAD)
        cfg.rdsDI_COMP = rds.bool("di_comp", defaultValue: cfg.rdsDI_COMP)
        cfg.rdsDI_DYN = rds.bool("di_dyn", defaultValue: cfg.rdsDI_DYN)
        cfg.rdsEnableAF = rds.bool("en_af", defaultValue: cfg.rdsEnableAF)
        cfg.rdsAFList = rds.string("af_list", defaultValue: cfg.rdsAFList)
        cfg.rdsAFMethod = rds.string("af_method", defaultValue: cfg.rdsAFMethod)
        cfg.rdsPSDynamic = rds.string("ps_dynamic", defaultValue: cfg.rdsPSDynamic)
        cfg.rdsPSCentered = rds.bool("ps_centered", defaultValue: cfg.rdsPSCentered)
        cfg.rdsRTText = rds.string("rt_text", defaultValue: cfg.rdsRTText)
        cfg.rdsRTManualBuffers = rds.bool("rt_manual_buffers", defaultValue: cfg.rdsRTManualBuffers)
        cfg.rdsRTCycleAB = rds.bool("rt_cycle_ab", defaultValue: cfg.rdsRTCycleAB)
        cfg.rdsRTA = rds.string("rt_a", defaultValue: cfg.rdsRTA)
        cfg.rdsRTB = rds.string("rt_b", defaultValue: cfg.rdsRTB)
        cfg.rdsRTCR = rds.bool("rt_cr", defaultValue: cfg.rdsRTCR)
        cfg.rdsRTCentered = rds.bool("rt_centered", defaultValue: cfg.rdsRTCentered)
        cfg.rdsRTMode = rds.string("rt_mode", defaultValue: cfg.rdsRTMode)
        cfg.rdsRTCycle = rds.bool("rt_cycle", defaultValue: cfg.rdsRTCycle)
        cfg.rdsRTCycleTime = rds.double("rt_cycle_time", defaultValue: cfg.rdsRTCycleTime)
        cfg.rdsRTActiveBuffer = rds.int("rt_active_buffer", defaultValue: cfg.rdsRTActiveBuffer)
        cfg.rdsRTABCycleCount = rds.int("rt_ab_cycle_count", defaultValue: cfg.rdsRTABCycleCount)
        cfg.rdsPTYN = rds.string("ptyn", defaultValue: cfg.rdsPTYN)
        cfg.rdsEnablePTYN = rds.bool("en_ptyn", defaultValue: cfg.rdsEnablePTYN)
        cfg.rdsPTYNCentered = rds.bool("ptyn_centered", defaultValue: cfg.rdsPTYNCentered)
        cfg.rdsLongPS32 = rds.string("ps_long_32", defaultValue: cfg.rdsLongPS32)
        cfg.rdsEnableLPS = rds.bool("en_lps", defaultValue: cfg.rdsEnableLPS)
        cfg.rdsLPSCentered = rds.bool("lps_centered", defaultValue: cfg.rdsLPSCentered)
        cfg.rdsLPSCR = rds.bool("lps_cr", defaultValue: cfg.rdsLPSCR)
        cfg.rdsEnableRTPlus = rds.bool("en_rt_plus", defaultValue: cfg.rdsEnableRTPlus)
        cfg.rdsRTPlusFormatA = rds.string("rt_plus_format_a", defaultValue: cfg.rdsRTPlusFormatA)
        cfg.rdsRTPlusFormatB = rds.string("rt_plus_format_b", defaultValue: cfg.rdsRTPlusFormatB)
        cfg.rdsECC = rds.string("ecc", defaultValue: cfg.rdsECC)
        cfg.rdsLIC = rds.string("lic", defaultValue: cfg.rdsLIC)
        cfg.rdsTZOffset = rds.double("tz_offset", defaultValue: cfg.rdsTZOffset)
        cfg.rdsEnableCT = rds.bool("en_ct", defaultValue: cfg.rdsEnableCT)
        cfg.rdsEnableID = rds.bool("en_id", defaultValue: cfg.rdsEnableID)
        cfg.rdsAutoStart = rds.bool("auto_start", defaultValue: cfg.rdsAutoStart)
        cfg.rdsGroupSequence = rds.string("group_sequence", defaultValue: cfg.rdsGroupSequence)
        cfg.rdsSchedulerAuto = rds.bool("scheduler_auto", defaultValue: cfg.rdsSchedulerAuto)
        cfg.rdsSchedulerStandard = rds.bool(
            "scheduler_standard", defaultValue: cfg.rdsSchedulerStandard)
        cfg.rdsSchedulerStandardLPS = rds.bool(
            "scheduler_standard_lps", defaultValue: cfg.rdsSchedulerStandardLPS)
        cfg.rdsFreq = rds.double("rds_freq", defaultValue: cfg.rdsFreq)
        cfg.rdsGaussianEnabled = rds.bool(
            "rds_gaussian_enabled", defaultValue: cfg.rdsGaussianEnabled)
        cfg.rdsGaussianBWHZ = rds.double("rds_gaussian_bw_hz", defaultValue: cfg.rdsGaussianBWHZ)
        cfg.rdsGaussianTaps = rds.int("rds_gaussian_taps", defaultValue: cfg.rdsGaussianTaps)
        cfg.rdsPI = Self.sanitizedPICode(cfg.rdsPI)
        cfg.rdsPTY = max(0, min(31, cfg.rdsPTY))
        cfg.rdsRTMode = (cfg.rdsRTMode.uppercased() == "2B") ? "2B" : "2A"
        cfg.rdsRTCycleTime = max(1.0, min(60.0, cfg.rdsRTCycleTime))
        cfg.rdsRTActiveBuffer = max(0, min(1, cfg.rdsRTActiveBuffer))
        cfg.rdsRTABCycleCount = max(1, min(99, cfg.rdsRTABCycleCount))
        cfg.rdsECC = Self.sanitizedHexByte(cfg.rdsECC)
        cfg.rdsLIC = Self.sanitizedHexByte(cfg.rdsLIC)
        cfg.rdsTZOffset = max(-12.0, min(14.0, cfg.rdsTZOffset))
        cfg.rdsLevel = max(0.0, min(7.5, cfg.rdsLevel))
        cfg.rdsFreq = max(1_000.0, min(120_000.0, cfg.rdsFreq))
        cfg.rdsGaussianBWHZ = max(600.0, min(6_000.0, cfg.rdsGaussianBWHZ))
        cfg.rdsGaussianTaps = max(9, min(401, cfg.rdsGaussianTaps | 1))

        // Note: monitor_rate_hz only affects the optional monitoring audio capture, not main render rate
        // Main render rate uses the default sample_rate or is determined by hardware capability
        cfg.blockSize = max(2048, interfaces.int("blocksize", defaultValue: cfg.blockSize))
        cfg.fftWindow96kHz = interfaces.bool("fft_window_92khz", defaultValue: cfg.fftWindow96kHz)
        return cfg
    }

    static func resolvedINIPath(_ path: String, forWrite: Bool = false) -> String {
        resolveINIPath(path, forWrite: forWrite)
    }

    func save(toINI path: String) throws {
        let mpxLines: [String] = [
            "[MPX]",
            "pilot_level = \(Self.formatFloat(pilotLevel))",
            "sum_level = \(Self.formatFloat(sumLevel))",
            "diff_level = \(Self.formatFloat(diffLevel))",
            "mono_mode = \(Self.boolString(monoMode))",
            "processing_bypass = \(Self.boolString(processingBypass))",
            "preemphasis_us = \(preemphasisUS)",
            "program_lowpass_hz = \(Self.formatFloat(programLowpassHz))",
            "input_gain_db = \(Self.formatFloat(inputGainDB))",
            "output_gain_db = \(Self.formatFloat(outputGainDB))",
            "hpf_hz = \(Self.formatFloat(hpfHz))",
            "hf_trim_db = \(Self.formatFloat(hfTrimDB))",
            "hf_trim_hz = \(Self.formatFloat(hfTrimHz))",
            "limit_mpx = \(Self.boolString(limitMPX))",
            "limit_threshold = \(Self.formatFloat(limitThreshold))",
            "limit_lookahead_enabled = \(Self.boolString(limitLookaheadEnabled))",
            "limit_lookahead_ms = \(Self.formatFloat(limitLookaheadMS))",
            "composite_clipper_enabled = \(Self.boolString(compositeLimiterEnabled))",
            "mpx_deviation_khz = \(Self.formatFloat(mpxDeviationKHz))",
            "en_rds = \(Self.boolString(enRDS))",
            "wideband_agc_enabled = \(Self.boolString(widebandAGCEnabled))",
            "wideband_agc_target_db = \(Self.formatFloat(widebandAGCTargetDB))",
            "wideband_agc_attack_ms = \(Self.formatFloat(widebandAGCAttackMS))",
            "wideband_agc_release_ms = \(Self.formatFloat(widebandAGCReleaseMS))",
            "wideband_agc_max_gain_db = \(Self.formatFloat(widebandAGCMaxGainDB))",
            "wideband_agc_min_gain_db = \(Self.formatFloat(widebandAGCMinGainDB))",
            "orbass_enabled = \(Self.boolString(orbassEnabled))",
            "orbass_amount = \(Self.formatFloat(orbassAmount))",
            "orbass_freq_hz = \(Self.formatFloat(orbassFreqHz))",
            "orbass_harmonics = \(Self.formatFloat(orbassHarmonics))",
            "orbass_drive = \(Self.formatFloat(orbassDrive))",
            "orbass_density = \(Self.formatFloat(orbassDensity))",
            "orbass_subharmonics_enabled = \(Self.boolString(orbassSubharmonicsEnabled))",
            "orbass_subharmonics_amount = \(Self.formatFloat(orbassSubharmonicsAmount))",
            "stereo_widen_enabled = \(Self.boolString(stereoWidenEnabled))",
            "stereo_widen_width = \(Self.formatFloat(stereoWidenWidth))",
            "stereo_widen_center = \(Self.formatFloat(stereoWidenCenter))",
            "stereo_widen_mix = \(Self.formatFloat(stereoWidenMix))",
            "multiband_enabled = \(Self.boolString(multibandEnabled))",
            "multiband_mode = \(multibandMode)",
            "multiband_preset_id = \(multibandPresetID)",
            "multiband_intensity = \(multibandIntensity)",
            "multiband_low_hz = \(Self.formatFloat(multibandLowHz))",
            "multiband_high_hz = \(Self.formatFloat(multibandHighHz))",
            "multiband_x1_hz = \(Self.formatFloat(multibandX1Hz))",
            "multiband_x2_hz = \(Self.formatFloat(multibandX2Hz))",
            "multiband_x3_hz = \(Self.formatFloat(multibandX3Hz))",
            "multiband_x4_hz = \(Self.formatFloat(multibandX4Hz))",
            "multiband_low_threshold_db = \(Self.formatFloat(multibandLowThresholdDB))",
            "multiband_mid_threshold_db = \(Self.formatFloat(multibandMidThresholdDB))",
            "multiband_high_threshold_db = \(Self.formatFloat(multibandHighThresholdDB))",
            "multiband_low_ratio = \(Self.formatFloat(multibandLowRatio))",
            "multiband_mid_ratio = \(Self.formatFloat(multibandMidRatio))",
            "multiband_high_ratio = \(Self.formatFloat(multibandHighRatio))",
            "multiband_low_attack_ms = \(Self.formatFloat(multibandLowAttackMS))",
            "multiband_mid_attack_ms = \(Self.formatFloat(multibandMidAttackMS))",
            "multiband_high_attack_ms = \(Self.formatFloat(multibandHighAttackMS))",
            "multiband_low_release_ms = \(Self.formatFloat(multibandLowReleaseMS))",
            "multiband_mid_release_ms = \(Self.formatFloat(multibandMidReleaseMS))",
            "multiband_high_release_ms = \(Self.formatFloat(multibandHighReleaseMS))",
            "multiband_knee_db = \(Self.formatFloat(multibandKneeDB))",
            "multiband_link_strength = \(Self.formatFloat(multibandLinkStrength))",
            "multiband_release_program_dependent = \(Self.boolString(multibandReleaseProgramDependent))",
            "multiband_makeup_db = \(Self.formatFloat(multibandMakeupDB))",
            "test_tone_mode = \(testToneMode)",
            "test_tone_freq = \(Self.formatFloat(testToneFreq))",
        ]
        let rdsLines: [String] = [
            "[RDS]",
            "en_rds = \(Self.boolString(enRDS))",
            "rds_level = \(Self.formatFloat(rdsLevel))",
            "pi = \(Self.sanitizedPICode(rdsPI))",
            "pty = \(max(0, min(31, rdsPTY)))",
            "tp = \(Self.boolString(rdsTP))",
            "ta = \(Self.boolString(rdsTA))",
            "ms = \(Self.boolString(rdsMS))",
            "di_stereo = \(Self.boolString(rdsDI_STEREO))",
            "di_head = \(Self.boolString(rdsDI_HEAD))",
            "di_comp = \(Self.boolString(rdsDI_COMP))",
            "di_dyn = \(Self.boolString(rdsDI_DYN))",
            "en_af = \(Self.boolString(rdsEnableAF))",
            "af_list = \(rdsAFList)",
            "af_method = \(rdsAFMethod)",
            "ps_dynamic = \(rdsPSDynamic)",
            "ps_centered = \(Self.boolString(rdsPSCentered))",
            "rt_text = \(rdsRTText)",
            "rt_manual_buffers = \(Self.boolString(rdsRTManualBuffers))",
            "rt_cycle_ab = \(Self.boolString(rdsRTCycleAB))",
            "rt_a = \(rdsRTA)",
            "rt_b = \(rdsRTB)",
            "rt_cr = \(Self.boolString(rdsRTCR))",
            "rt_centered = \(Self.boolString(rdsRTCentered))",
            "rt_mode = \(rdsRTMode)",
            "rt_cycle = \(Self.boolString(rdsRTCycle))",
            "rt_cycle_time = \(Self.formatFloat(max(1.0, min(60.0, rdsRTCycleTime))))",
            "rt_active_buffer = \(max(0, min(1, rdsRTActiveBuffer)))",
            "rt_ab_cycle_count = \(max(1, min(99, rdsRTABCycleCount)))",
            "ptyn = \(rdsPTYN)",
            "en_ptyn = \(Self.boolString(rdsEnablePTYN))",
            "ptyn_centered = \(Self.boolString(rdsPTYNCentered))",
            "ps_long_32 = \(rdsLongPS32)",
            "en_lps = \(Self.boolString(rdsEnableLPS))",
            "lps_centered = \(Self.boolString(rdsLPSCentered))",
            "lps_cr = \(Self.boolString(rdsLPSCR))",
            "en_rt_plus = \(Self.boolString(rdsEnableRTPlus))",
            "rt_plus_format_a = \(rdsRTPlusFormatA)",
            "rt_plus_format_b = \(rdsRTPlusFormatB)",
            "ecc = \(Self.sanitizedHexByte(rdsECC))",
            "lic = \(Self.sanitizedHexByte(rdsLIC))",
            "tz_offset = \(Self.formatFloat(max(-12.0, min(14.0, rdsTZOffset))))",
            "en_ct = \(Self.boolString(rdsEnableCT))",
            "en_id = \(Self.boolString(rdsEnableID))",
            "auto_start = \(Self.boolString(rdsAutoStart))",
            "group_sequence = \(rdsGroupSequence)",
            "scheduler_auto = \(Self.boolString(rdsSchedulerAuto))",
            "scheduler_standard = \(Self.boolString(rdsSchedulerStandard))",
            "scheduler_standard_lps = \(Self.boolString(rdsSchedulerStandardLPS))",
            "rds_freq = \(Self.formatFloat(max(1_000.0, min(120_000.0, rdsFreq))))",
            "rds_gaussian_enabled = \(Self.boolString(rdsGaussianEnabled))",
            "rds_gaussian_bw_hz = \(Self.formatFloat(max(600.0, min(6_000.0, rdsGaussianBWHZ))))",
            "rds_gaussian_taps = \(max(9, min(401, rdsGaussianTaps | 1)))",
        ]
        let interfacesLines: [String] = [
            "[INTERFACES]",
            "source_mode = \(sourceMode)",
            "monitor_enabled = \(Self.boolString(monitorEnabled))",
            "monitor_rate_hz = \(Self.formatFloat(sampleRate))",
            "blocksize = \(blockSize)",
            "fft_window_92khz = \(Self.boolString(fftWindow96kHz))",
            "input_device_uid = \(inputDeviceUID ?? "")",
            "output_device_uid = \(outputDeviceUID ?? "")",
            "monitor_device_uid = \(monitorDeviceUID ?? "")",
        ]
        let text = (mpxLines + [""] + rdsLines + [""] + interfacesLines + [""]).joined(
            separator: "\n")
        let resolvedPath = Self.resolveINIPath(path, forWrite: true)
        let fileManager = FileManager.default
        let parentDirectory = URL(fileURLWithPath: resolvedPath).deletingLastPathComponent().path
        if !parentDirectory.isEmpty && parentDirectory != "/" {
            try fileManager.createDirectory(
                atPath: parentDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        try text.write(toFile: resolvedPath, atomically: true, encoding: .utf8)
    }

    private static func boolString(_ value: Bool) -> String {
        value ? "True" : "False"
    }

    private static func formatFloat(_ value: Double) -> String {
        if value.rounded() == value {
            return String(format: "%.1f", value)
        }
        return String(format: "%.6g", value)
    }

    private static func sanitizedPICode(_ raw: String) -> String {
        let upper = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let filtered = upper.filter { ch in
            switch ch {
            case "0"..."9", "A"..."F":
                return true
            default:
                return false
            }
        }
        if filtered.isEmpty {
            return "0000"
        }
        if filtered.count >= 4 {
            return String(filtered.prefix(4))
        }
        return String(repeating: "0", count: 4 - filtered.count) + filtered
    }

    private static func sanitizedHexByte(_ raw: String) -> String {
        let upper = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let filtered = upper.filter { ch in
            switch ch {
            case "0"..."9", "A"..."F":
                return true
            default:
                return false
            }
        }
        if filtered.isEmpty {
            return "00"
        }
        if filtered.count >= 2 {
            return String(filtered.suffix(2))
        }
        return "0" + filtered
    }

    private static func resolveINIPath(_ rawPath: String, forWrite: Bool) -> String {
        let expandedPath = (rawPath as NSString).expandingTildeInPath
        let expandedNSString = expandedPath as NSString
        if expandedNSString.isAbsolutePath {
            return expandedNSString.standardizingPath
        }

        let fileManager = FileManager.default
        var candidates: [String] = []
        var seen: Set<String> = []

        func appendCandidate(_ candidate: String) {
            let normalized = (candidate as NSString).standardizingPath
            if seen.insert(normalized).inserted {
                candidates.append(normalized)
            }
        }

        func appendRelativeCandidate(base: String) {
            let combined = (base as NSString).appendingPathComponent(expandedPath)
            appendCandidate(combined)
        }

        // Check PWD environment variable first (respects shell launch context)
        if let pwdEnv = ProcessInfo.processInfo.environment["PWD"], !pwdEnv.isEmpty {
            appendRelativeCandidate(base: pwdEnv)
        }

        appendRelativeCandidate(base: fileManager.currentDirectoryPath)

        if let execPath = CommandLine.arguments.first, !execPath.isEmpty {
            var base = (execPath as NSString).deletingLastPathComponent
            while !base.isEmpty {
                appendRelativeCandidate(base: base)
                let parent = (base as NSString).deletingLastPathComponent
                if parent == base {
                    break
                }
                base = parent
            }
        }

        if let existingFile = candidates.first(where: { candidate in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: candidate, isDirectory: &isDirectory) else {
                return false
            }
            return !isDirectory.boolValue
        }) {
            return existingFile
        }

        if forWrite {
            if let writableCandidate = candidates.first(where: { candidate in
                let parent = (candidate as NSString).deletingLastPathComponent
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: parent, isDirectory: &isDirectory) else {
                    return false
                }
                return isDirectory.boolValue
            }) {
                return writableCandidate
            }
        }

        if let firstCandidate = candidates.first {
            return firstCandidate
        }
        let fallback = (fileManager.currentDirectoryPath as NSString).appendingPathComponent(
            expandedPath)
        return (fallback as NSString).standardizingPath
    }
}

extension Dictionary where Key == String, Value == String {
    fileprivate func string(_ key: String, defaultValue: String) -> String {
        guard let raw = self[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty
        else {
            return defaultValue
        }
        return raw
    }

    fileprivate func optionalString(_ key: String) -> String? {
        guard let raw = self[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty
        else {
            return nil
        }
        return raw
    }

    fileprivate func double(_ key: String, defaultValue: Double) -> Double {
        guard let raw = self[key],
            let val = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return defaultValue
        }
        return val
    }

    fileprivate func int(_ key: String, defaultValue: Int) -> Int {
        guard let raw = self[key],
            let val = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return defaultValue
        }
        return val
    }

    fileprivate func bool(_ key: String, defaultValue: Bool) -> Bool {
        guard let raw = self[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        else {
            return defaultValue
        }
        switch raw {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return defaultValue
        }
    }
}
