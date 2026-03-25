import AVFoundation
import AudioToolbox
import Foundation
import Accelerate

enum AudioEngineError: Error {
    case sourceNodeFormatUnavailable
    case engineStartFailed(String)
    case inputFormatUnavailable
    case deviceSelectionFailed(String)
}

enum AudioOutputMode {
    case mpxComposite
    case monitorAudio
}

final class AudioOutputEngine {
    private static let scopeSampleCount = 128
    private static let scopeHistorySeconds: Double = 0.25
    private static let meterUpdateIntervalFrames: Int = 512

    struct MeterSnapshot {
        var inputRMS: Float
        var inputPeak: Float
        var inputLeftRMS: Float
        var inputRightRMS: Float
        var inputLeftPeak: Float
        var inputRightPeak: Float
        var outputRMS: Float
        var outputPeak: Float
        var deviationKHzPeak: Float
        var liveInputPeak: Float
        var liveInputLeftPeak: Float
        var liveInputRightPeak: Float
        var liveOutputPeak: Float
        var liveDeviationKHzPeak: Float
        var agcDetectorDB: Float
        var agcGainDB: Float
        var agcGateActive: Bool
        var compositeLimiterGainReductionDB: Float
        var mpxSafetyLimiterGainReductionDB: Float
        var pilotInjectionPercent: Float
        var rdsInjectionPercent: Float
        var audioCompositePeak: Float
        var compositeBudgetMarginDB: Float
        var outputStereoCorrelation: Float
        var outputSideToMidRatio: Float
        var loudnessAvailable: Bool
        var loudnessMomentaryLUFS: Float
        var loudnessShortTermLUFS: Float
        var loudnessIntegratedLUFS: Float
    }

    private struct LoudnessSnapshot {
        var available: Bool = false
        var momentaryLUFS: Float = -120.0
        var shortTermLUFS: Float = -120.0
        var integratedLUFS: Float = -120.0
    }

    private final class MonitorLoudnessAnalyzer {
        private static let blockDurationSeconds: Double = 0.1
        private static let momentaryBlockCount = 4
        private static let shortTermBlockCount = 30
        private static let silenceGateLUFS: Float = -70.0
        private static let relativeGateOffsetLU: Float = -10.0

        private let sampleRate: Float
        private let blockFrameTarget: Int
        private var kWeightHP = StereoBiquad()
        private var kWeightShelf = StereoBiquad()
        private var partialBlockEnergy: Double = 0.0
        private var partialBlockFrames: Int = 0
        private var completedBlockMeanSquares: [Double] = []

        init(sampleRate: Float) {
            self.sampleRate = max(8_000.0, sampleRate)
            self.blockFrameTarget = max(
                1,
                Int((Self.blockDurationSeconds * Double(self.sampleRate)).rounded())
            )
            reset()
        }

        func reset() {
            partialBlockEnergy = 0.0
            partialBlockFrames = 0
            completedBlockMeanSquares.removeAll(keepingCapacity: false)
            kWeightHP.configureHighpass(cutoffHz: 38.0, sampleRate: sampleRate)
            kWeightShelf.configureHighShelf(gainDB: 4.0, cutoffHz: 1_680.0, sampleRate: sampleRate)
        }

        func process(left: UnsafePointer<Float>, right: UnsafePointer<Float>, frameCount: Int) {
            guard frameCount > 0 else { return }
            for i in 0..<frameCount {
                let highPassed = kWeightHP.process(left: left[i], right: right[i])
                let weighted = kWeightShelf.process(left: highPassed.0, right: highPassed.1)
                partialBlockEnergy += Double((weighted.0 * weighted.0) + (weighted.1 * weighted.1))
                partialBlockFrames += 1
                if partialBlockFrames >= blockFrameTarget {
                    completedBlockMeanSquares.append(partialBlockEnergy / Double(partialBlockFrames))
                    partialBlockEnergy = 0.0
                    partialBlockFrames = 0
                }
            }
        }

        func snapshot() -> LoudnessSnapshot {
            guard completedBlockMeanSquares.count >= Self.momentaryBlockCount else {
                return LoudnessSnapshot()
            }
            let momentary = rollingLufs(lastBlocks: Self.momentaryBlockCount)
            let shortTerm = rollingLufs(lastBlocks: Self.shortTermBlockCount)
            let integrated = integratedLufs()
            return LoudnessSnapshot(
                available: true,
                momentaryLUFS: momentary,
                shortTermLUFS: shortTerm,
                integratedLUFS: integrated
            )
        }

        private func rollingLufs(lastBlocks: Int) -> Float {
            let blocks = min(lastBlocks, completedBlockMeanSquares.count)
            guard blocks > 0 else { return -120.0 }
            let slice = completedBlockMeanSquares.suffix(blocks)
            let meanSquare = slice.reduce(0.0, +) / Double(blocks)
            return Self.lufs(meanSquare: meanSquare)
        }

        private func integratedLufs() -> Float {
            let gatingBlocks = overlapping400msBlocks()
            guard !gatingBlocks.isEmpty else { return -120.0 }

            let absoluteGated = gatingBlocks.filter { Self.lufs(meanSquare: $0) >= Self.silenceGateLUFS }
            guard !absoluteGated.isEmpty else { return -120.0 }

            let absoluteMeanSquare = absoluteGated.reduce(0.0, +) / Double(absoluteGated.count)
            let absoluteLufs = Self.lufs(meanSquare: absoluteMeanSquare)
            let relativeGate = absoluteLufs + Self.relativeGateOffsetLU
            let relativeGated = absoluteGated.filter { Self.lufs(meanSquare: $0) >= relativeGate }
            guard !relativeGated.isEmpty else { return absoluteLufs }

            let integratedMeanSquare = relativeGated.reduce(0.0, +) / Double(relativeGated.count)
            return Self.lufs(meanSquare: integratedMeanSquare)
        }

        private func overlapping400msBlocks() -> [Double] {
            guard completedBlockMeanSquares.count >= Self.momentaryBlockCount else { return [] }
            var blocks: [Double] = []
            blocks.reserveCapacity(completedBlockMeanSquares.count - Self.momentaryBlockCount + 1)
            for start in 0...(completedBlockMeanSquares.count - Self.momentaryBlockCount) {
                let window = completedBlockMeanSquares[start..<(start + Self.momentaryBlockCount)]
                blocks.append(window.reduce(0.0, +) / Double(Self.momentaryBlockCount))
            }
            return blocks
        }

        private static func lufs(meanSquare: Double) -> Float {
            guard meanSquare.isFinite, meanSquare > 1e-12 else { return -120.0 }
            return Float(-0.691 + (10.0 * log10(meanSquare)))
        }
    }

    private let engine = AVAudioEngine()
    private var captureEngine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private let generator: MPXGenerator
    private let useInputSource: Bool
    private let requestedSampleRate: Double
    private let requestedBlockSize: Int
    private let requestedInputDeviceID: AudioDeviceID?
    private let requestedOutputDeviceID: AudioDeviceID?
    private let outputMode: AudioOutputMode
    private let targetDeviationKHz: Float
    private var configuredRenderSampleRate: Double = 0.0
    private var inputRing: StereoInputRingBuffer?
    private var captureTapInstalled = false
    private var configuredInputSampleRate: Double?
    private var inputToRenderRatio: Double = 1.0
    private var inputPrefillFrames = 0
    private var inputPrimed = false
    private var inputTargetBufferedFrames = 0
    private var inputBufferedDeadbandFrames = 0
    private var routingNote: String?
    private var captureCallbackCount: UInt64 = 0
    private var captureFrameCount: UInt64 = 0
    private var captureFrameCounter: Int = 0
    private let meterLock = NSLock()
    private let runtimeConfigLock = NSLock()
    private var meterSnapshot = MeterSnapshot(
        inputRMS: 0.0,
        inputPeak: 0.0,
        inputLeftRMS: 0.0,
        inputRightRMS: 0.0,
        inputLeftPeak: 0.0,
        inputRightPeak: 0.0,
        outputRMS: 0.0,
        outputPeak: 0.0,
        deviationKHzPeak: 0.0,
        liveInputPeak: 0.0,
        liveInputLeftPeak: 0.0,
        liveInputRightPeak: 0.0,
        liveOutputPeak: 0.0,
        liveDeviationKHzPeak: 0.0,
        agcDetectorDB: -120.0,
        agcGainDB: 0.0,
        agcGateActive: false,
        compositeLimiterGainReductionDB: 0.0,
        mpxSafetyLimiterGainReductionDB: 0.0,
        pilotInjectionPercent: 0.0,
        rdsInjectionPercent: 0.0,
        audioCompositePeak: 0.0,
        compositeBudgetMarginDB: 0.0,
        outputStereoCorrelation: 1.0,
        outputSideToMidRatio: 0.0,
        loudnessAvailable: false,
        loudnessMomentaryLUFS: -120.0,
        loudnessShortTermLUFS: -120.0,
        loudnessIntegratedLUFS: -120.0
    )
    private var loudnessAnalyzer: MonitorLoudnessAnalyzer?
    private var pendingInputPeak: Float = 0.0
    private var pendingInputLeftPeak: Float = 0.0
    private var pendingInputRightPeak: Float = 0.0
    private var pendingOutputPeak: Float = 0.0
    private var lastMeterReadUptime: TimeInterval?
    private var inputScopeHistory: [Float] = []
    private var outputScopeHistory: [Float] = []
    private var inputScopeWriteIndex: Int = 0
    private var outputScopeWriteIndex: Int = 0
    private var inputScopeValidFrames: Int = 0
    private var outputScopeValidFrames: Int = 0
    private var inputScopeSampleRate: Double = 0.0
    private var outputScopeSampleRate: Double = 0.0
    private var monitorMPXLeftScratch: [Float] = []
    private var monitorMPXRightScratch: [Float] = []
    private var isShuttingDown = false
    private var frameCounter: Int = 0
    private var meteringEnabled: Bool = true
    private var inputConversionBuffer: [Float] = []
    private var inputConversionBufferStereoL: [Float] = []
    private var inputConversionBufferStereoR: [Float] = []
    private var pendingRuntimeConfig: MPXGenerator.RuntimeConfig?

    init(
        generator: MPXGenerator,
        config: AppConfig,
        inputDeviceID: AudioDeviceID? = nil,
        outputDeviceID: AudioDeviceID? = nil,
        outputMode: AudioOutputMode = .mpxComposite
    ) {
        self.generator = generator
        self.useInputSource = config.sourceMode.lowercased() == "input"
        self.requestedSampleRate = config.sampleRate
        self.requestedBlockSize = config.blockSize
        self.requestedInputDeviceID = inputDeviceID
        self.requestedOutputDeviceID = outputDeviceID
        self.outputMode = outputMode
        self.targetDeviationKHz = Float(max(1.0, config.mpxDeviationKHz))
    }

    func start() throws {
        isShuttingDown = false
        meteringEnabled = true
        try applyOutputDeviceSelection()
        let outputRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let requestedRate = max(8_000.0, requestedSampleRate)
        let renderRate = (outputMode == .monitorAudio) ? requestedRate : outputRate
        if useInputSource {
            try setupInputCapture(targetSampleRate: renderRate)
        }
        if outputMode == .mpxComposite, outputRate < 110_000.0 {
            appendRoutingNote(
                "Output sample rate is too low for stereo MPX. Use a 192 kHz-capable output device."
            )
        }
        if outputMode == .monitorAudio, fabs(outputRate - renderRate) > 1.0 {
            appendRoutingNote(
                "Monitor hardware is \(Int(outputRate.rounded())) Hz; internal MPX render remains \(Int(renderRate.rounded())) Hz."
            )
        }
        configuredRenderSampleRate = renderRate
        generator.setSampleRate(renderRate)
        loudnessAnalyzer = MonitorLoudnessAnalyzer(sampleRate: Float(renderRate))
        configureScopeHistory(renderRate: renderRate, inputRate: configuredInputSampleRate)
        preAllocateBuffers(maxFrames: Int(max(renderRate, 192000.0) * 0.1))

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: renderRate,
            channels: 2,
            interleaved: false
        )
        guard let sourceFormat = format else {
            throw AudioEngineError.sourceNodeFormatUnavailable
        }
        let node = AVAudioSourceNode(format: sourceFormat) {
            [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else {
                Self.clearBuffers(audioBufferList, frameCount: Int(frameCount))
                return noErr
            }
            if self.isShuttingDown {
                Self.clearBuffers(audioBufferList, frameCount: Int(frameCount))
                return noErr
            }
            self.applyPendingRuntimeConfigIfNeeded()
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let frames = Int(frameCount)
            self.frameCounter += frames
            let throttled = self.meteringEnabled && ((self.frameCounter % Self.meterUpdateIntervalFrames) < frames)
            if buffers.count >= 2,
                let leftData = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                let rightData = buffers[1].mData?.assumingMemoryBound(to: Float.self)
            {
                if self.useInputSource, let ring = self.inputRing {
                    if !self.inputPrimed {
                        if ring.bufferedFrames() < self.inputPrefillFrames {
                            for i in 0..<frames {
                                leftData[i] = 0.0
                                rightData[i] = 0.0
                            }
                            return noErr
                        }
                        self.inputPrimed = true
                    }
                    let missing = ring.readAdaptive(
                        intoLeft: leftData,
                        outRight: rightData,
                        frameCount: frames,
                        nominalConsume: max(
                            1, Int((Double(frames) * self.inputToRenderRatio).rounded())),
                        targetBuffered: self.inputTargetBufferedFrames,
                        deadband: self.inputBufferedDeadbandFrames
                    )
                    if missing >= max(1, frames / 4) {
                        self.inputPrimed = false
                    }
                    if self.outputMode == .monitorAudio {
                        if self.generator.isProcessingBypassEnabled {
                            self.generator.renderMonitorFromInputInPlace(
                                frameCount: frames,
                                left: leftData,
                                right: rightData
                            )
                            self.updateMonitorLoudness(left: leftData, right: rightData, frameCount: frames)
                            let outMeter = Self.computeStereoMeter(
                                left: leftData, right: rightData, frameCount: frames)
                            if throttled {
                                self.updateOutputMeters(
                                    outputRMS: outMeter.rms, outputPeak: outMeter.peak)
                                self.updateOutputImageMetrics(
                                    correlation: outMeter.correlation,
                                    sideToMidRatio: outMeter.sideToMidRatio
                                )
                                self.updateOutputScopeSnapshot(
                                    left: leftData, right: rightData, frameCount: frames)
                            }
                        } else {
                            self.ensureMonitorScratchCapacity(frames: frames)
                            self.monitorMPXLeftScratch.withUnsafeMutableBufferPointer { mpxL in
                                self.monitorMPXRightScratch.withUnsafeMutableBufferPointer { mpxR in
                                    guard let mpxLeft = mpxL.baseAddress,
                                        let mpxRight = mpxR.baseAddress
                                    else { return }
                                    self.generator.renderFromInputAndMonitorInPlace(
                                        frameCount: frames,
                                        left: leftData,
                                        right: rightData,
                                        mpxLeft: mpxLeft,
                                        mpxRight: mpxRight
                                    )
                                    self.updateMonitorLoudness(left: leftData, right: rightData, frameCount: frames)
                                    let outMeter = Self.computeStereoMeter(
                                        left: mpxLeft, right: mpxRight, frameCount: frames)
                                    if throttled {
                                        self.updateOutputMeters(
                                            outputRMS: outMeter.rms, outputPeak: outMeter.peak)
                                        self.updateOutputImageMetrics(
                                            correlation: outMeter.correlation,
                                            sideToMidRatio: outMeter.sideToMidRatio
                                        )
                                        self.updateOutputScopeSnapshot(
                                            left: mpxLeft, right: mpxRight, frameCount: frames)
                                    }
                                }
                            }
                        }
                    } else {
                        self.generator.renderFromInputInPlace(
                            frameCount: frames,
                            left: leftData,
                            right: rightData
                        )
                        let outMeter = Self.computeStereoMeter(
                            left: leftData, right: rightData, frameCount: frames)
                        if throttled {
                            self.updateOutputMeters(outputRMS: outMeter.rms, outputPeak: outMeter.peak)
                            self.updateOutputImageMetrics(
                                correlation: outMeter.correlation,
                                sideToMidRatio: outMeter.sideToMidRatio
                            )
                            self.updateOutputScopeSnapshot(
                                left: leftData, right: rightData, frameCount: frames)
                        }
                    }
                    if throttled, !self.useInputSource {
                        self.updateInputScopeSnapshot(
                            left: leftData, right: rightData, frameCount: frames)
                    }
                } else {
                    if self.outputMode == .monitorAudio {
                        if self.generator.isProcessingBypassEnabled {
                            self.generator.renderMonitorToneNonInterleaved(
                                frameCount: frames,
                                left: leftData,
                                right: rightData
                            )
                            self.updateMonitorLoudness(left: leftData, right: rightData, frameCount: frames)
                            let outMeter = Self.computeStereoMeter(
                                left: leftData, right: rightData, frameCount: frames)
                            if throttled {
                                self.updateOutputMeters(
                                    outputRMS: outMeter.rms, outputPeak: outMeter.peak)
                                self.updateOutputImageMetrics(
                                    correlation: outMeter.correlation,
                                    sideToMidRatio: outMeter.sideToMidRatio
                                )
                                self.updateOutputScopeSnapshot(
                                    left: leftData, right: rightData, frameCount: frames)
                            }
                        } else {
                            self.ensureMonitorScratchCapacity(frames: frames)
                            self.monitorMPXLeftScratch.withUnsafeMutableBufferPointer { mpxL in
                                self.monitorMPXRightScratch.withUnsafeMutableBufferPointer { mpxR in
                                    guard let mpxLeft = mpxL.baseAddress,
                                        let mpxRight = mpxR.baseAddress
                                    else { return }
                                    self.generator.renderToneAndMonitorNonInterleaved(
                                        frameCount: frames,
                                        left: leftData,
                                        right: rightData,
                                        mpxLeft: mpxLeft,
                                        mpxRight: mpxRight
                                    )
                                    self.updateMonitorLoudness(left: leftData, right: rightData, frameCount: frames)
                                    let outMeter = Self.computeStereoMeter(
                                        left: mpxLeft, right: mpxRight, frameCount: frames)
                                    if throttled {
                                        self.updateOutputMeters(
                                            outputRMS: outMeter.rms, outputPeak: outMeter.peak)
                                        self.updateOutputImageMetrics(
                                            correlation: outMeter.correlation,
                                            sideToMidRatio: outMeter.sideToMidRatio
                                        )
                                        self.updateOutputScopeSnapshot(
                                            left: mpxLeft, right: mpxRight, frameCount: frames)
                                    }
                                }
                            }
                        }
                    } else {
                        self.generator.renderNonInterleaved(
                            frameCount: frames,
                            left: leftData,
                            right: rightData
                        )
                        let outMeter = Self.computeStereoMeter(
                            left: leftData, right: rightData, frameCount: frames)
                        if throttled {
                            self.updateOutputMeters(outputRMS: outMeter.rms, outputPeak: outMeter.peak)
                            self.updateOutputImageMetrics(
                                correlation: outMeter.correlation,
                                sideToMidRatio: outMeter.sideToMidRatio
                            )
                            self.updateOutputScopeSnapshot(
                                left: leftData, right: rightData, frameCount: frames)
                        }
                    }
                    if throttled, !self.useInputSource {
                        self.updateInputScopeSnapshot(
                            left: leftData, right: rightData, frameCount: frames)
                    }
                }
                return noErr
            }
            if buffers.count == 1,
                let data = buffers[0].mData?.assumingMemoryBound(to: Float.self)
            {
                // Interleaved fallback path.
                for i in 0..<(frames * 2) {
                    data[i] = 0.0
                }
                return noErr
            }
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: sourceFormat)
        engine.mainMixerNode.outputVolume = 1.0
        sourceNode = node

        do {
            try engine.start()
        } catch {
            throw AudioEngineError.engineStartFailed(error.localizedDescription)
        }
    }

    func stop() {
        isShuttingDown = false
        meteringEnabled = false
        inputRing = nil
        engine.stop()
        engine.reset()
        if let capture = captureEngine {
            capture.stop()
            if captureTapInstalled {
                capture.inputNode.removeTap(onBus: 0)
                captureTapInstalled = false
            }
            capture.reset()
            captureEngine = nil
        }
        inputPrimed = false
        configuredInputSampleRate = nil
        inputToRenderRatio = 1.0
        sourceNode = nil
        frameCounter = 0
        captureFrameCounter = 0
        meterLock.lock()
        pendingInputPeak = 0.0
        pendingInputLeftPeak = 0.0
        pendingInputRightPeak = 0.0
        pendingOutputPeak = 0.0
        lastMeterReadUptime = nil
        runtimeConfigLock.lock()
        pendingRuntimeConfig = nil
        runtimeConfigLock.unlock()
        meterSnapshot.inputRMS = 0.0
        meterSnapshot.inputPeak = 0.0
        meterSnapshot.inputLeftRMS = 0.0
        meterSnapshot.inputRightRMS = 0.0
        meterSnapshot.inputLeftPeak = 0.0
        meterSnapshot.inputRightPeak = 0.0
        meterSnapshot.outputRMS = 0.0
        meterSnapshot.outputPeak = 0.0
        meterSnapshot.deviationKHzPeak = 0.0
        meterSnapshot.agcDetectorDB = -120.0
        meterSnapshot.agcGainDB = 0.0
        meterSnapshot.agcGateActive = false
        meterSnapshot.compositeLimiterGainReductionDB = 0.0
        meterSnapshot.mpxSafetyLimiterGainReductionDB = 0.0
        meterSnapshot.pilotInjectionPercent = 0.0
        meterSnapshot.rdsInjectionPercent = 0.0
        meterSnapshot.audioCompositePeak = 0.0
        meterSnapshot.compositeBudgetMarginDB = 0.0
        meterSnapshot.outputStereoCorrelation = 1.0
        meterSnapshot.outputSideToMidRatio = 0.0
        meterSnapshot.liveInputPeak = 0.0
        meterSnapshot.liveInputLeftPeak = 0.0
        meterSnapshot.liveInputRightPeak = 0.0
        meterSnapshot.liveOutputPeak = 0.0
        meterSnapshot.liveDeviationKHzPeak = 0.0
        meterSnapshot.loudnessAvailable = false
        meterSnapshot.loudnessMomentaryLUFS = -120.0
        meterSnapshot.loudnessShortTermLUFS = -120.0
        meterSnapshot.loudnessIntegratedLUFS = -120.0
        loudnessAnalyzer?.reset()
        inputScopeHistory = []
        outputScopeHistory = []
        inputScopeWriteIndex = 0
        outputScopeWriteIndex = 0
        inputScopeValidFrames = 0
        outputScopeValidFrames = 0
        inputScopeSampleRate = 0.0
        outputScopeSampleRate = 0.0
        monitorMPXLeftScratch = []
        monitorMPXRightScratch = []
        meterLock.unlock()
        isShuttingDown = false
    }

    private func applyOutputDeviceSelection() throws {
        routingNote = nil
        if let outputID = requestedOutputDeviceID {
            do {
                try setCurrentDevice(outputID, for: engine.outputNode, role: "output")
            } catch {
                routingNote =
                    "Requested output device could not be opened by AVAudioEngine; using macOS default output."
            }
        }
    }

    private func setupInputCapture(targetSampleRate: Double) throws {
        let capture = AVAudioEngine()
        if let inputID = requestedInputDeviceID {
            try setCurrentDevice(inputID, for: capture.inputNode, role: "input")
        }
        let inFormat = capture.inputNode.inputFormat(forBus: 0)
        if inFormat.channelCount < 1 {
            throw AudioEngineError.inputFormatUnavailable
        }
        configuredInputSampleRate = inFormat.sampleRate
        if targetSampleRate > 1.0 {
            inputToRenderRatio = max(0.25, min(4.0, inFormat.sampleRate / targetSampleRate))
        } else {
            inputToRenderRatio = 1.0
        }
        let captureBlockFrames = min(2048, max(256, requestedBlockSize))
        let ringFrames = max(captureBlockFrames * 128, Int(inFormat.sampleRate * 1.0))
        let ring = StereoInputRingBuffer(capacityFrames: ringFrames)
        inputRing = ring
        inputPrefillFrames = max(captureBlockFrames * 12, 4096)
        inputTargetBufferedFrames = max(inputPrefillFrames * 2, captureBlockFrames * 24)
        inputBufferedDeadbandFrames = max(captureBlockFrames * 4, 1024)
        inputPrimed = false
        let tapFormat = inFormat
        capture.inputNode.installTap(
            onBus: 0,
            bufferSize: AVAudioFrameCount(captureBlockFrames),
            format: tapFormat
        ) { [weak self] buffer, _ in
            guard let self, let activeRing = self.inputRing else { return }
            self.pushInputBufferToRing(buffer, ring: activeRing)
        }
        captureTapInstalled = true
        do {
            try capture.start()
        } catch {
            throw AudioEngineError.engineStartFailed(
                "input capture start failed: \(error.localizedDescription)")
        }
        captureEngine = capture
    }

    private func ensureMonitorScratchCapacity(frames: Int) {
        guard frames > 0 else { return }
        if monitorMPXLeftScratch.count < frames {
            monitorMPXLeftScratch = Array(repeating: 0.0, count: frames)
        }
        if monitorMPXRightScratch.count < frames {
            monitorMPXRightScratch = Array(repeating: 0.0, count: frames)
        }
    }

    private func preAllocateBuffers(maxFrames: Int) {
        let safeFrames = max(512, maxFrames)
        monitorMPXLeftScratch = [Float](repeating: 0.0, count: safeFrames)
        monitorMPXRightScratch = [Float](repeating: 0.0, count: safeFrames)
        inputConversionBuffer = [Float](repeating: 0.0, count: safeFrames)
        inputConversionBufferStereoL = [Float](repeating: 0.0, count: safeFrames)
        inputConversionBufferStereoR = [Float](repeating: 0.0, count: safeFrames)
    }

    private func ensureInputConversionCapacity(frames: Int) {
        guard frames > 0 else { return }
        if inputConversionBuffer.count < frames {
            inputConversionBuffer = [Float](repeating: 0.0, count: frames)
        }
        if inputConversionBufferStereoL.count < frames {
            inputConversionBufferStereoL = [Float](repeating: 0.0, count: frames)
        }
        if inputConversionBufferStereoR.count < frames {
            inputConversionBufferStereoR = [Float](repeating: 0.0, count: frames)
        }
    }

    private func appendRoutingNote(_ note: String) {
        if let current = routingNote, !current.isEmpty {
            routingNote = current + " " + note
        } else {
            routingNote = note
        }
    }

    private func pushInputBufferToRing(_ buffer: AVAudioPCMBuffer, ring: StereoInputRingBuffer) {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        captureCallbackCount += 1
        captureFrameCount += UInt64(frames)
        captureFrameCounter += frames
        let throttled = meteringEnabled && ((captureFrameCounter % Self.meterUpdateIntervalFrames) < frames)
        let chanCount = Int(buffer.format.channelCount)
        let isInterleaved = buffer.format.isInterleaved
        if let channels = buffer.floatChannelData {
            if chanCount >= 2 {
                ring.write(left: channels[0], right: channels[1], frameCount: frames)
                if throttled {
                    let meter = Self.computeStereoMeter(
                        left: channels[0], right: channels[1], frameCount: frames)
                    updateInputMeters(
                        inputRMS: meter.rms,
                        inputPeak: meter.peak,
                        inputLeftRMS: meter.leftRMS,
                        inputRightRMS: meter.rightRMS,
                        inputLeftPeak: meter.leftPeak,
                        inputRightPeak: meter.rightPeak
                    )
                    updateInputScopeSnapshot(left: channels[0], right: channels[1], frameCount: frames)
                }
            } else {
                ring.writeMono(mono: channels[0], frameCount: frames)
                if throttled {
                    let meter = Self.computeMonoMeter(samples: channels[0], frameCount: frames)
                    updateInputMeters(
                        inputRMS: meter.rms,
                        inputPeak: meter.peak,
                        inputLeftRMS: meter.rms,
                        inputRightRMS: meter.rms,
                        inputLeftPeak: meter.peak,
                        inputRightPeak: meter.peak
                    )
                    updateInputScopeSnapshot(mono: channels[0], frameCount: frames)
                }
            }
            return
        }
        if let channels = buffer.int16ChannelData {
            let scale: Float = 1.0 / 32768.0
            ensureInputConversionCapacity(frames: frames)
            if chanCount >= 2 {
                for i in 0..<frames {
                    inputConversionBufferStereoL[i] = Float(channels[0][i]) * scale
                    inputConversionBufferStereoR[i] = Float(channels[1][i]) * scale
                }
            } else {
                for i in 0..<frames {
                    let s = Float(channels[0][i]) * scale
                    inputConversionBufferStereoL[i] = s
                    inputConversionBufferStereoR[i] = s
                }
            }
            inputConversionBufferStereoL.withUnsafeBufferPointer { l in
                inputConversionBufferStereoR.withUnsafeBufferPointer { r in
                    ring.write(left: l.baseAddress!, right: r.baseAddress!, frameCount: frames)
                    if throttled {
                        let meter = Self.computeStereoMeter(
                            left: l.baseAddress!, right: r.baseAddress!, frameCount: frames)
                        updateInputMeters(
                            inputRMS: meter.rms,
                            inputPeak: meter.peak,
                            inputLeftRMS: meter.leftRMS,
                            inputRightRMS: meter.rightRMS,
                            inputLeftPeak: meter.leftPeak,
                            inputRightPeak: meter.rightPeak
                        )
                        updateInputScopeSnapshot(
                            left: l.baseAddress!, right: r.baseAddress!, frameCount: frames)
                    }
                }
            }
            return
        }
        if let channels = buffer.int32ChannelData {
            let scale: Float = 1.0 / 2147483648.0
            ensureInputConversionCapacity(frames: frames)
            if chanCount >= 2 {
                for i in 0..<frames {
                    inputConversionBufferStereoL[i] = Float(channels[0][i]) * scale
                    inputConversionBufferStereoR[i] = Float(channels[1][i]) * scale
                }
            } else {
                for i in 0..<frames {
                    let s = Float(channels[0][i]) * scale
                    inputConversionBufferStereoL[i] = s
                    inputConversionBufferStereoR[i] = s
                }
            }
            inputConversionBufferStereoL.withUnsafeBufferPointer { l in
                inputConversionBufferStereoR.withUnsafeBufferPointer { r in
                    ring.write(left: l.baseAddress!, right: r.baseAddress!, frameCount: frames)
                    if throttled {
                        let meter = Self.computeStereoMeter(
                            left: l.baseAddress!, right: r.baseAddress!, frameCount: frames)
                        updateInputMeters(
                            inputRMS: meter.rms,
                            inputPeak: meter.peak,
                            inputLeftRMS: meter.leftRMS,
                            inputRightRMS: meter.rightRMS,
                            inputLeftPeak: meter.leftPeak,
                            inputRightPeak: meter.rightPeak
                        )
                        updateInputScopeSnapshot(
                            left: l.baseAddress!, right: r.baseAddress!, frameCount: frames)
                    }
                }
            }
            return
        }
        let audioBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        if isInterleaved, audioBuffers.count == 1, let mData = audioBuffers[0].mData {
            ensureInputConversionCapacity(frames: frames)
            switch buffer.format.commonFormat {
            case .pcmFormatFloat32:
                let interleaved = mData.assumingMemoryBound(to: Float.self)
                if chanCount >= 2 {
                    for i in 0..<frames {
                        inputConversionBufferStereoL[i] = interleaved[i * chanCount]
                        inputConversionBufferStereoR[i] = interleaved[i * chanCount + 1]
                    }
                } else {
                    for i in 0..<frames {
                        let s = interleaved[i]
                        inputConversionBufferStereoL[i] = s
                        inputConversionBufferStereoR[i] = s
                    }
                }
            case .pcmFormatInt16:
                let interleaved = mData.assumingMemoryBound(to: Int16.self)
                let scale: Float = 1.0 / 32768.0
                if chanCount >= 2 {
                    for i in 0..<frames {
                        inputConversionBufferStereoL[i] = Float(interleaved[i * chanCount]) * scale
                        inputConversionBufferStereoR[i] = Float(interleaved[i * chanCount + 1]) * scale
                    }
                } else {
                    for i in 0..<frames {
                        let s = Float(interleaved[i]) * scale
                        inputConversionBufferStereoL[i] = s
                        inputConversionBufferStereoR[i] = s
                    }
                }
            case .pcmFormatInt32:
                let interleaved = mData.assumingMemoryBound(to: Int32.self)
                let scale: Float = 1.0 / 2147483648.0
                if chanCount >= 2 {
                    for i in 0..<frames {
                        inputConversionBufferStereoL[i] = Float(interleaved[i * chanCount]) * scale
                        inputConversionBufferStereoR[i] = Float(interleaved[i * chanCount + 1]) * scale
                    }
                } else {
                    for i in 0..<frames {
                        let s = Float(interleaved[i]) * scale
                        inputConversionBufferStereoL[i] = s
                        inputConversionBufferStereoR[i] = s
                    }
                }
            default:
                return
            }
            inputConversionBufferStereoL.withUnsafeBufferPointer { l in
                inputConversionBufferStereoR.withUnsafeBufferPointer { r in
                    ring.write(left: l.baseAddress!, right: r.baseAddress!, frameCount: frames)
                    if throttled {
                        let meter = Self.computeStereoMeter(
                            left: l.baseAddress!, right: r.baseAddress!, frameCount: frames)
                        updateInputMeters(
                            inputRMS: meter.rms,
                            inputPeak: meter.peak,
                            inputLeftRMS: meter.leftRMS,
                            inputRightRMS: meter.rightRMS,
                            inputLeftPeak: meter.leftPeak,
                            inputRightPeak: meter.rightPeak
                        )
                        updateInputScopeSnapshot(
                            left: l.baseAddress!, right: r.baseAddress!, frameCount: frames)
                    }
                }
            }
        }
    }

    private func setCurrentDevice(_ deviceID: AudioDeviceID, for node: AVAudioIONode, role: String)
        throws
    {
        guard let audioUnit = node.audioUnit else {
            throw AudioEngineError.deviceSelectionFailed("\(role) audio unit unavailable")
        }
        var mutableID = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableID,
            size
        )
        if status != noErr {
            let be = UInt32(bitPattern: status)
            let c1 = Character(UnicodeScalar((be >> 24) & 0xFF)!)
            let c2 = Character(UnicodeScalar((be >> 16) & 0xFF)!)
            let c3 = Character(UnicodeScalar((be >> 8) & 0xFF)!)
            let c4 = Character(UnicodeScalar(be & 0xFF)!)
            throw AudioEngineError.deviceSelectionFailed(
                "\(role) device set failed status=\(status) fourcc=\(c1)\(c2)\(c3)\(c4)"
            )
        }
    }

    var hardwareSampleRate: Double {
        engine.outputNode.outputFormat(forBus: 0).sampleRate
    }

    var hardwareChannels: Int {
        Int(engine.outputNode.outputFormat(forBus: 0).channelCount)
    }

    var blockSize: Int {
        requestedBlockSize
    }

    var renderSampleRate: Double {
        configuredRenderSampleRate > 0 ? configuredRenderSampleRate : requestedSampleRate
    }

    var inputSampleRate: Double? {
        configuredInputSampleRate
    }

    var inputStats: (overflows: UInt64, underflows: UInt64, bufferedFrames: Int)? {
        inputRing?.stats()
    }

    var inputTargetFrames: Int {
        inputTargetBufferedFrames
    }

    func setMeteringEnabled(_ enabled: Bool) {
        meteringEnabled = enabled
    }

    func applyRuntimeConfig(_ config: AppConfig) {
        let runtime = MPXGenerator.RuntimeConfig(
            inputGainDB: Float(config.inputGainDB),
            outputGainDB: Float(config.outputGainDB),
            finalDriveDB: Float(config.finalDriveDB),
            widebandAGCEnabled: config.widebandAGCEnabled,
            widebandAGCTargetDB: Float(config.widebandAGCTargetDB),
            widebandAGCMaxGainDB: Float(config.widebandAGCMaxGainDB),
            widebandAGCMinGainDB: Float(config.widebandAGCMinGainDB),
            widebandAGCAttackMS: Float(config.widebandAGCAttackMS),
            widebandAGCReleaseMS: Float(config.widebandAGCReleaseMS),
            compositeLimiterEnabled: config.compositeLimiterEnabled,
            mpxDeviationKHz: Float(config.mpxDeviationKHz),
            orbassEnabled: config.orbassEnabled,
            orbassAmount: Float(config.orbassAmount),
            orbassHarmonics: Float(config.orbassHarmonics),
            orbassDrive: Float(config.orbassDrive),
            orbassDensity: Float(config.orbassDensity),
            orbassSubharmonicsEnabled: config.orbassSubharmonicsEnabled,
            orbassSubharmonicsAmount: Float(config.orbassSubharmonicsAmount),
            orbassFreqHz: Float(config.orbassFreqHz),
            stereoWidenEnabled: config.stereoWidenEnabled,
            monoBassEnabled: config.monoBassEnabled,
            monoBassFreqHz: Float(config.monoBassFreqHz),
            widenWidth: Float(config.stereoWidenWidth),
            widenCenter: Float(config.stereoWidenCenter),
            widenMix: Float(config.stereoWidenMix),
            multibandEnabled: config.multibandEnabled,
            multibandMode: config.multibandMode,
            multibandMakeupDB: Float(config.multibandMakeupDB),
            multibandKneeDB: Float(config.multibandKneeDB),
            multibandLinkStrength: Float(config.multibandLinkStrength),
            multibandReleaseProgramDependent: config.multibandReleaseProgramDependent,
            multibandX1Hz: Float(config.multibandX1Hz),
            multibandX2Hz: Float(config.multibandX2Hz),
            multibandX3Hz: Float(config.multibandX3Hz),
            multibandX4Hz: Float(config.multibandX4Hz),
            multibandLowThresholdDB: Float(config.multibandLowThresholdDB),
            multibandMidThresholdDB: Float(config.multibandMidThresholdDB),
            multibandHighThresholdDB: Float(config.multibandHighThresholdDB),
            multibandLowRatio: Float(config.multibandLowRatio),
            multibandMidRatio: Float(config.multibandMidRatio),
            multibandHighRatio: Float(config.multibandHighRatio),
            multibandLowAttackMS: Float(config.multibandLowAttackMS),
            multibandMidAttackMS: Float(config.multibandMidAttackMS),
            multibandHighAttackMS: Float(config.multibandHighAttackMS),
            multibandLowReleaseMS: Float(config.multibandLowReleaseMS),
            multibandMidReleaseMS: Float(config.multibandMidReleaseMS),
            multibandHighReleaseMS: Float(config.multibandHighReleaseMS)
        )
        runtimeConfigLock.lock()
        pendingRuntimeConfig = runtime
        runtimeConfigLock.unlock()
    }

    var meters: MeterSnapshot {
        meterLock.lock()
        let nowUptime = ProcessInfo.processInfo.systemUptime
        let dt = max(0.0, min(1.0, nowUptime - (lastMeterReadUptime ?? (nowUptime - 0.2))))
        lastMeterReadUptime = nowUptime
        // Keep peak hold decay stable regardless of UI polling frequency.
        let decayPerSecond: Float = 0.47
        let decayFactor = powf(decayPerSecond, Float(dt))
        let pendingInput = pendingInputPeak.isFinite ? max(0.0, pendingInputPeak) : 0.0
        let pendingInputLeft = pendingInputLeftPeak.isFinite ? max(0.0, pendingInputLeftPeak) : 0.0
        let pendingInputRight =
            pendingInputRightPeak.isFinite ? max(0.0, pendingInputRightPeak) : 0.0
        let pendingOutput = pendingOutputPeak.isFinite ? max(0.0, pendingOutputPeak) : 0.0
        let decayedInput =
            meterSnapshot.inputPeak.isFinite ? max(0.0, meterSnapshot.inputPeak * decayFactor) : 0.0
        let decayedInputLeft =
            meterSnapshot.inputLeftPeak.isFinite
            ? max(0.0, meterSnapshot.inputLeftPeak * decayFactor) : 0.0
        let decayedInputRight =
            meterSnapshot.inputRightPeak.isFinite
            ? max(0.0, meterSnapshot.inputRightPeak * decayFactor) : 0.0
        let decayedOutput =
            meterSnapshot.outputPeak.isFinite
            ? max(0.0, meterSnapshot.outputPeak * decayFactor) : 0.0
        let inputPeak = max(pendingInput, decayedInput)
        let inputLeftPeak = max(pendingInputLeft, decayedInputLeft)
        let inputRightPeak = max(pendingInputRight, decayedInputRight)
        let outputPeak = max(pendingOutput, decayedOutput)
        meterSnapshot.inputRMS =
            meterSnapshot.inputRMS.isFinite ? max(0.0, meterSnapshot.inputRMS) : 0.0
        meterSnapshot.inputLeftRMS =
            meterSnapshot.inputLeftRMS.isFinite ? max(0.0, meterSnapshot.inputLeftRMS) : 0.0
        meterSnapshot.inputRightRMS =
            meterSnapshot.inputRightRMS.isFinite ? max(0.0, meterSnapshot.inputRightRMS) : 0.0
        meterSnapshot.outputRMS =
            meterSnapshot.outputRMS.isFinite ? max(0.0, meterSnapshot.outputRMS) : 0.0
        meterSnapshot.inputPeak = inputPeak
        meterSnapshot.inputLeftPeak = inputLeftPeak
        meterSnapshot.inputRightPeak = inputRightPeak
        meterSnapshot.outputPeak = outputPeak
        meterSnapshot.deviationKHzPeak = outputPeak * targetDeviationKHz
        meterSnapshot.liveInputPeak = pendingInput
        meterSnapshot.liveInputLeftPeak = pendingInputLeft
        meterSnapshot.liveInputRightPeak = pendingInputRight
        meterSnapshot.liveOutputPeak = pendingOutput
        meterSnapshot.liveDeviationKHzPeak = pendingOutput * targetDeviationKHz
        if let loudness = loudnessAnalyzer?.snapshot() {
            meterSnapshot.loudnessAvailable = loudness.available
            meterSnapshot.loudnessMomentaryLUFS = loudness.momentaryLUFS
            meterSnapshot.loudnessShortTermLUFS = loudness.shortTermLUFS
            meterSnapshot.loudnessIntegratedLUFS = loudness.integratedLUFS
        } else {
            meterSnapshot.loudnessAvailable = false
            meterSnapshot.loudnessMomentaryLUFS = -120.0
            meterSnapshot.loudnessShortTermLUFS = -120.0
            meterSnapshot.loudnessIntegratedLUFS = -120.0
        }
        pendingInputPeak = 0.0
        pendingInputLeftPeak = 0.0
        pendingInputRightPeak = 0.0
        pendingOutputPeak = 0.0
        let snapshot = meterSnapshot
        meterLock.unlock()
        return snapshot
    }

    var captureStats: (callbacks: UInt64, frames: UInt64) {
        meterLock.lock()
        let cbs = captureCallbackCount
        let fr = captureFrameCount
        meterLock.unlock()
        return (cbs, fr)
    }

    var scopeSnapshot: (input: [Float], output: [Float]) {
        scopeSnapshot(windowMS: 20.0)
    }

    func scopeSnapshot(windowMS: Double) -> (input: [Float], output: [Float]) {
        meterLock.lock()
        let input = Self.renderScopeWindow(
            from: inputScopeHistory,
            writeIndex: inputScopeWriteIndex,
            validFrames: inputScopeValidFrames,
            sampleRate: inputScopeSampleRate,
            windowMS: windowMS
        )
        let output = Self.renderScopeWindow(
            from: outputScopeHistory,
            writeIndex: outputScopeWriteIndex,
            validFrames: outputScopeValidFrames,
            sampleRate: outputScopeSampleRate,
            windowMS: windowMS
        )
        meterLock.unlock()
        return (input, output)
    }

    func outputSignalWindow(frameCount: Int) -> (samples: [Float], sampleRate: Double) {
        meterLock.lock()
        let sr = max(1_000.0, outputScopeSampleRate)
        let data = Self.renderRawWindow(
            from: outputScopeHistory,
            writeIndex: outputScopeWriteIndex,
            validFrames: outputScopeValidFrames,
            frameCount: frameCount
        )
        meterLock.unlock()
        return (data, sr)
    }

    var sourceDescription: String {
        useInputSource ? "input" : "tone"
    }

    var deviceRoutingNote: String? {
        routingNote
    }

    private func updateMeters(
        inputRMS: Float, inputPeak: Float, outputRMS: Float, outputPeak: Float
    ) {
        let agc = generator.agcStatus
        let limiter = generator.finalLimiterStatus
        let calibration = generator.compositeCalibrationStatus
        meterSnapshot = MeterSnapshot(
            inputRMS: inputRMS,
            inputPeak: inputPeak,
            inputLeftRMS: inputRMS,
            inputRightRMS: inputRMS,
            inputLeftPeak: inputPeak,
            inputRightPeak: inputPeak,
            outputRMS: outputRMS,
            outputPeak: outputPeak,
            deviationKHzPeak: outputPeak * targetDeviationKHz,
            liveInputPeak: inputPeak,
            liveInputLeftPeak: inputPeak,
            liveInputRightPeak: inputPeak,
            liveOutputPeak: outputPeak,
            liveDeviationKHzPeak: outputPeak * targetDeviationKHz,
            agcDetectorDB: agc.detectorDB,
            agcGainDB: agc.gainDB,
            agcGateActive: agc.gateActive,
            compositeLimiterGainReductionDB: limiter.gainReductionDB,
            mpxSafetyLimiterGainReductionDB: limiter.safetyGainReductionDB,
            pilotInjectionPercent: calibration.pilotPercent,
            rdsInjectionPercent: calibration.rdsPercent,
            audioCompositePeak: calibration.audioPeak,
            compositeBudgetMarginDB: calibration.budgetMarginDB,
            outputStereoCorrelation: 1.0,
            outputSideToMidRatio: 0.0
            ,
            loudnessAvailable: false,
            loudnessMomentaryLUFS: -120.0,
            loudnessShortTermLUFS: -120.0,
            loudnessIntegratedLUFS: -120.0
        )
    }

    private func updateInputMeters(
        inputRMS: Float,
        inputPeak: Float,
        inputLeftRMS: Float,
        inputRightRMS: Float,
        inputLeftPeak: Float,
        inputRightPeak: Float
    ) {
        meterSnapshot.inputRMS = inputRMS.isFinite ? max(0.0, inputRMS) : 0.0
        meterSnapshot.inputLeftRMS = inputLeftRMS.isFinite ? max(0.0, inputLeftRMS) : 0.0
        meterSnapshot.inputRightRMS = inputRightRMS.isFinite ? max(0.0, inputRightRMS) : 0.0
        let safePeak = inputPeak.isFinite ? max(0.0, inputPeak) : 0.0
        let safeLeftPeak = inputLeftPeak.isFinite ? max(0.0, inputLeftPeak) : 0.0
        let safeRightPeak = inputRightPeak.isFinite ? max(0.0, inputRightPeak) : 0.0
        if safePeak > pendingInputPeak {
            pendingInputPeak = safePeak
        }
        if safeLeftPeak > pendingInputLeftPeak {
            pendingInputLeftPeak = safeLeftPeak
        }
        if safeRightPeak > pendingInputRightPeak {
            pendingInputRightPeak = safeRightPeak
        }
    }

    private func updateOutputMeters(outputRMS: Float, outputPeak: Float) {
        meterSnapshot.outputRMS = outputRMS
        let agc = generator.agcStatus
        let limiter = generator.finalLimiterStatus
        let calibration = generator.compositeCalibrationStatus
        meterSnapshot.agcDetectorDB = agc.detectorDB
        meterSnapshot.agcGainDB = agc.gainDB
        meterSnapshot.agcGateActive = agc.gateActive
        meterSnapshot.compositeLimiterGainReductionDB = limiter.gainReductionDB
        meterSnapshot.mpxSafetyLimiterGainReductionDB = limiter.safetyGainReductionDB
        meterSnapshot.pilotInjectionPercent = calibration.pilotPercent
        meterSnapshot.rdsInjectionPercent = calibration.rdsPercent
        meterSnapshot.audioCompositePeak = calibration.audioPeak
        meterSnapshot.compositeBudgetMarginDB = calibration.budgetMarginDB
        if outputPeak > pendingOutputPeak {
            pendingOutputPeak = outputPeak
        }
    }

    private func updateMonitorLoudness(
        left: UnsafePointer<Float>,
        right: UnsafePointer<Float>,
        frameCount: Int
    ) {
        loudnessAnalyzer?.process(left: left, right: right, frameCount: frameCount)
    }

    private func applyPendingRuntimeConfigIfNeeded() {
        runtimeConfigLock.lock()
        let runtime = pendingRuntimeConfig
        pendingRuntimeConfig = nil
        runtimeConfigLock.unlock()
        if let runtime {
            generator.applyRuntimeConfig(runtime)
        }
    }

    private func updateOutputImageMetrics(correlation: Float, sideToMidRatio: Float) {
        meterSnapshot.outputStereoCorrelation =
            correlation.isFinite ? Self.clamp(correlation, -1.0, 1.0) : 0.0
        meterSnapshot.outputSideToMidRatio = sideToMidRatio.isFinite ? max(0.0, sideToMidRatio) : 0.0
    }

    private func updateInputScopeSnapshot(
        left: UnsafePointer<Float>, right: UnsafePointer<Float>, frameCount: Int
    ) {
        guard frameCount > 0 else { return }
        appendStereoScopeSamples(
            left: left,
            right: right,
            frameCount: frameCount,
            into: &inputScopeHistory,
            writeIndex: &inputScopeWriteIndex,
            validFrames: &inputScopeValidFrames
        )
    }

    private func updateInputScopeSnapshot(mono: UnsafePointer<Float>, frameCount: Int) {
        guard frameCount > 0 else { return }
        appendMonoScopeSamples(
            samples: mono,
            frameCount: frameCount,
            into: &inputScopeHistory,
            writeIndex: &inputScopeWriteIndex,
            validFrames: &inputScopeValidFrames
        )
    }

    private func updateOutputScopeSnapshot(
        left: UnsafePointer<Float>, right: UnsafePointer<Float>, frameCount: Int
    ) {
        guard frameCount > 0 else { return }
        appendStereoScopeSamples(
            left: left,
            right: right,
            frameCount: frameCount,
            into: &outputScopeHistory,
            writeIndex: &outputScopeWriteIndex,
            validFrames: &outputScopeValidFrames
        )
    }

    private func configureScopeHistory(renderRate: Double, inputRate: Double?) {
        let safeRenderRate = max(1_000.0, renderRate)
        let safeInputRate = max(1_000.0, inputRate ?? renderRate)
        let outputCapacity = max(
            Self.scopeSampleCount * 8, Int((safeRenderRate * Self.scopeHistorySeconds).rounded()))
        let inputCapacity = max(
            Self.scopeSampleCount * 8, Int((safeInputRate * Self.scopeHistorySeconds).rounded()))

        meterLock.lock()
        outputScopeHistory = Array(repeating: 0.0, count: outputCapacity)
        outputScopeWriteIndex = 0
        outputScopeValidFrames = 0
        outputScopeSampleRate = safeRenderRate

        inputScopeHistory = Array(repeating: 0.0, count: inputCapacity)
        inputScopeWriteIndex = 0
        inputScopeValidFrames = 0
        inputScopeSampleRate = safeInputRate
        meterLock.unlock()
    }

    private func appendStereoScopeSamples(
        left: UnsafePointer<Float>,
        right: UnsafePointer<Float>,
        frameCount: Int,
        into history: inout [Float],
        writeIndex: inout Int,
        validFrames: inout Int
    ) {
        guard !history.isEmpty, frameCount > 0 else { return }
        var idx = writeIndex
        for i in 0..<frameCount {
            let sample = Self.clampf((left[i] + right[i]) * 0.5, -1.0, 1.0)
            history[idx] = sample
            idx += 1
            if idx >= history.count {
                idx = 0
            }
        }
        writeIndex = idx
        validFrames = min(history.count, validFrames + frameCount)
    }

    private func appendMonoScopeSamples(
        samples: UnsafePointer<Float>,
        frameCount: Int,
        into history: inout [Float],
        writeIndex: inout Int,
        validFrames: inout Int
    ) {
        guard !history.isEmpty, frameCount > 0 else { return }
        var idx = writeIndex
        for i in 0..<frameCount {
            let sample = Self.clampf(samples[i], -1.0, 1.0)
            history[idx] = sample
            idx += 1
            if idx >= history.count {
                idx = 0
            }
        }
        writeIndex = idx
        validFrames = min(history.count, validFrames + frameCount)
    }

    private static func renderScopeWindow(
        from history: [Float],
        writeIndex: Int,
        validFrames: Int,
        sampleRate: Double,
        windowMS: Double
    ) -> [Float] {
        guard !history.isEmpty, validFrames > 1 else {
            return Array(repeating: 0.0, count: scopeSampleCount)
        }

        let sr = max(1_000.0, sampleRate)
        let clampedWindowMS = max(1.0, min(250.0, windowMS))
        let requestedFrames = Int(((clampedWindowMS / 1000.0) * sr).rounded())
        let windowFrames = max(scopeSampleCount, min(validFrames, requestedFrames))
        let windowStart = (writeIndex - windowFrames + history.count) % history.count

        var output = Array(repeating: Float.zero, count: scopeSampleCount)
        for bucket in 0..<scopeSampleCount {
            let start = Int(
                (Double(bucket) * Double(windowFrames) / Double(scopeSampleCount)).rounded(.down))
            let end = max(
                start + 1,
                Int(
                    (Double(bucket + 1) * Double(windowFrames) / Double(scopeSampleCount)).rounded(
                        .down))
            )
            var representative: Float = 0.0
            for offset in start..<min(windowFrames, end) {
                let idx = (windowStart + offset) % history.count
                let sample = history[idx]
                if fabsf(sample) > fabsf(representative) {
                    representative = sample
                }
            }
            output[bucket] = representative
        }
        return output
    }

    private static func renderRawWindow(
        from history: [Float],
        writeIndex: Int,
        validFrames: Int,
        frameCount: Int
    ) -> [Float] {
        guard !history.isEmpty, validFrames > 0, frameCount > 0 else { return [] }
        let n = max(1, min(validFrames, frameCount))
        let start = (writeIndex - n + history.count) % history.count
        var output = Array(repeating: Float.zero, count: n)
        for i in 0..<n {
            output[i] = history[(start + i) % history.count]
        }
        return output
    }

    private static func computeStereoMeter(
        left: UnsafePointer<Float>,
        right: UnsafePointer<Float>,
        frameCount: Int
    ) -> (
        rms: Float,
        peak: Float,
        leftRMS: Float,
        rightRMS: Float,
        leftPeak: Float,
        rightPeak: Float,
        correlation: Float,
        sideToMidRatio: Float
    ) {
        guard frameCount > 0 else { return (0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0) }
        
        var sumL: Float = 0.0
        var sumR: Float = 0.0
        var peakL: Float = 0.0
        var peakR: Float = 0.0
        var dotLR: Float = 0.0
        var midEnergy: Float = 0.0
        var sideEnergy: Float = 0.0
        
        vDSP_svesq(left, 1, &sumL, vDSP_Length(frameCount))
        vDSP_svesq(right, 1, &sumR, vDSP_Length(frameCount))
        vDSP_maxmgv(left, 1, &peakL, vDSP_Length(frameCount))
        vDSP_maxmgv(right, 1, &peakR, vDSP_Length(frameCount))
        vDSP_dotpr(left, 1, right, 1, &dotLR, vDSP_Length(frameCount))

        for i in 0..<frameCount {
            let mid = (left[i] + right[i]) * 0.5
            let side = (left[i] - right[i]) * 0.5
            midEnergy += mid * mid
            sideEnergy += side * side
        }
        
        let rmsL = sqrtf(sumL / Float(frameCount))
        let rmsR = sqrtf(sumR / Float(frameCount))
        let correlation = dotLR / max(1e-9, sqrtf(sumL * sumR))
        let sideToMidRatio = sqrtf(sideEnergy / max(1e-9, midEnergy))
        return (
            sqrtf((rmsL * rmsL + rmsR * rmsR) * 0.5),
            max(peakL, peakR),
            rmsL,
            rmsR,
            peakL,
            peakR,
            correlation,
            sideToMidRatio
        )
    }

    @inline(__always)
    private static func clamp(_ x: Float, _ lo: Float, _ hi: Float) -> Float {
        return max(lo, min(hi, x))
    }

    private static func computeMonoMeter(
        samples: UnsafePointer<Float>,
        frameCount: Int
    ) -> (rms: Float, peak: Float) {
        guard frameCount > 0 else { return (0.0, 0.0) }
        
        var sum: Float = 0.0
        var peak: Float = 0.0
        
        vDSP_svesq(samples, 1, &sum, vDSP_Length(frameCount))
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(frameCount))
        
        return (sqrtf(sum / Float(frameCount)), peak)
    }

    private static func clearBuffers(
        _ audioBufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: Int
    ) {
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard frameCount > 0 else { return }
        if buffers.count >= 2,
            let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
            let right = buffers[1].mData?.assumingMemoryBound(to: Float.self)
        {
            vDSP_vclr(left, 1, vDSP_Length(frameCount))
            vDSP_vclr(right, 1, vDSP_Length(frameCount))
            return
        }
        if buffers.count == 1,
            let mono = buffers[0].mData?.assumingMemoryBound(to: Float.self)
        {
            vDSP_vclr(mono, 1, vDSP_Length(frameCount * 2))
        }
    }

    private static func clampf(_ x: Float, _ lo: Float, _ hi: Float) -> Float {
        return max(lo, min(hi, x))
    }
}
