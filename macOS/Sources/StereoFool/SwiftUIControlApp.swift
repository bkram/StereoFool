import Accelerate
import AppKit
import Combine
import CoreAudio
import Darwin
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// Sizes
private let kWindowWidth: CGFloat = 860
private let kWindowHeight: CGFloat = 440
private let kWindowMinWidth: CGFloat = 760
private let kWindowMinHeight: CGFloat = 380
private let kLevelsWindowWidth: CGFloat = 860
private let kLevelsWindowHeight: CGFloat = 560
private let kLevelsWindowMinWidth: CGFloat = 760
private let kLevelsWindowMinHeight: CGFloat = 500
private let kStereoFoolIconSymbol = "\u{1F3A7}"
private let kMainWindowAutosaveName = "StereoFool.MainWindow"
private let kScopesWindowAutosaveName = "StereoFool.ScopesWindow"
private let kSpectrumWindowAutosaveName = "StereoFool.SpectrumWindow"
private let kLevelsWindowAutosaveName = "StereoFool.LevelsWindow"
private let kAboutWindowAutosaveName = "StereoFool.AboutWindow"
private let kHelpWindowAutosaveName = "StereoFool.HelpWindow"
private let kSettingsWindowAutosaveName = "StereoFool.SettingsWindow"
private let kRestartRequiredSettingsListText =
    "Restart required for sample rate, block size, source mode, monitor output routing, input/output/monitor device changes, mono mode, pre-emphasis, pilot/sum/diff levels, program lowpass, and other encoder-structure changes."

private func makeStereoFoolAppIcon(size: CGFloat = 512) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let bounds = NSRect(origin: .zero, size: image.size)
    let inset = size * 0.07
    let rect = bounds.insetBy(dx: inset, dy: inset)
    let radius = size * 0.22

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = size * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -(size * 0.015))
    shadow.set()

    let panelPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.63, alpha: 1.0),
        NSColor(calibratedRed: 0.04, green: 0.16, blue: 0.28, alpha: 1.0),
    ])?.draw(in: panelPath, angle: -90)

    NSGraphicsContext.current?.saveGraphicsState()
    panelPath.addClip()

    NSColor.white.withAlphaComponent(0.10).setStroke()
    let borderPath = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.006, dy: size * 0.006), xRadius: radius, yRadius: radius)
    borderPath.lineWidth = size * 0.012
    borderPath.stroke()

    let center = NSPoint(x: bounds.midX, y: bounds.midY)
    let symbolFont = NSFont(name: "Apple Color Emoji", size: size * 0.42)
        ?? NSFont.systemFont(ofSize: size * 0.42, weight: .black)
    let shadowStyle = NSShadow()
    shadowStyle.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadowStyle.shadowBlurRadius = size * 0.02
    shadowStyle.shadowOffset = NSSize(width: 0, height: -(size * 0.012))
    let symbolAttributes: [NSAttributedString.Key: Any] = [
        .font: symbolFont,
        .foregroundColor: NSColor(calibratedWhite: 0.98, alpha: 1.0),
        .shadow: shadowStyle,
    ]
    let symbol = NSAttributedString(string: kStereoFoolIconSymbol, attributes: symbolAttributes)
    let symbolSize = symbol.size()
    let symbolRect = NSRect(
        x: center.x - (symbolSize.width / 2),
        y: center.y - (symbolSize.height / 2) - (size * 0.03),
        width: symbolSize.width,
        height: symbolSize.height
    )
    symbol.draw(in: symbolRect)

    let waveform = NSBezierPath()
    let waveformColor = NSColor(calibratedRed: 0.34, green: 0.84, blue: 0.77, alpha: 0.95)
    let waveformLineWidth = size * 0.022
    let waveformY = rect.maxY - (size * 0.14)
    let waveformLeft = rect.minX + (size * 0.16)
    let waveformWidth = rect.width - (size * 0.32)
    waveform.move(to: NSPoint(x: waveformLeft, y: waveformY))
    waveform.curve(
        to: NSPoint(x: waveformLeft + (waveformWidth * 0.2), y: waveformY),
        controlPoint1: NSPoint(x: waveformLeft + (waveformWidth * 0.05), y: waveformY),
        controlPoint2: NSPoint(x: waveformLeft + (waveformWidth * 0.12), y: waveformY - (size * 0.035))
    )
    waveform.curve(
        to: NSPoint(x: waveformLeft + (waveformWidth * 0.4), y: waveformY),
        controlPoint1: NSPoint(x: waveformLeft + (waveformWidth * 0.28), y: waveformY + (size * 0.055)),
        controlPoint2: NSPoint(x: waveformLeft + (waveformWidth * 0.34), y: waveformY + (size * 0.01))
    )
    waveform.curve(
        to: NSPoint(x: waveformLeft + (waveformWidth * 0.62), y: waveformY),
        controlPoint1: NSPoint(x: waveformLeft + (waveformWidth * 0.47), y: waveformY - (size * 0.06)),
        controlPoint2: NSPoint(x: waveformLeft + (waveformWidth * 0.55), y: waveformY - (size * 0.015))
    )
    waveform.curve(
        to: NSPoint(x: waveformLeft + (waveformWidth * 0.8), y: waveformY),
        controlPoint1: NSPoint(x: waveformLeft + (waveformWidth * 0.69), y: waveformY + (size * 0.05)),
        controlPoint2: NSPoint(x: waveformLeft + (waveformWidth * 0.75), y: waveformY + (size * 0.015))
    )
    waveform.curve(
        to: NSPoint(x: waveformLeft + waveformWidth, y: waveformY),
        controlPoint1: NSPoint(x: waveformLeft + (waveformWidth * 0.88), y: waveformY - (size * 0.035)),
        controlPoint2: NSPoint(x: waveformLeft + (waveformWidth * 0.95), y: waveformY)
    )
    waveform.lineWidth = waveformLineWidth
    waveform.lineCapStyle = .round
    waveform.lineJoinStyle = .round
    waveformColor.setStroke()
    waveform.stroke()

    NSGraphicsContext.current?.restoreGraphicsState()
    image.unlockFocus()
    return image
}

private struct MonitoringStatusLine: View {
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isRunning ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            
            Text(isRunning ? "Running" : "Stopped")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case monitoring = "Monitoring"
    case processing = "Processing"
    case rds = "RDS"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .monitoring: return "waveform"
        case .processing: return "slider.horizontal.3"
        case .rds: return "dot.radiowaves.left.and.right"
        }
    }

    var detailTitle: String { rawValue }

    var detailSubtitle: String {
        switch self {
        case .monitoring:
            return "Overview and live status"
        case .processing:
            return "DSP controls and presets"
        case .rds:
            return "Program service and carrier settings"
        }
    }
}

enum ProcessingTab: String, CaseIterable, Identifiable {
    case core = "Core"
    case agc = "AGC"
    case orbass = "Orbass"
    case multiband = "Multiband"
    case widener = "Widener"
    case limiter = "Limiter"

    var id: String { rawValue }

    var resetButtonTitle: String {
        switch self {
        case .core:
            return "Reset Core Tab"
        case .agc:
            return "Reset AGC Tab"
        case .orbass:
            return "Reset Orbass Tab"
        case .multiband:
            return "Reset Multiband Tab"
        case .widener:
            return "Reset Widener Tab"
        case .limiter:
            return "Reset Limiter Tab"
        }
    }

    var resetStatusText: String {
        switch self {
        case .core:
            return "Reset processing core tab to defaults"
        case .agc:
            return "Reset AGC tab to defaults"
        case .orbass:
            return "Reset Orbass tab to defaults"
        case .multiband:
            return "Reset Multiband tab to defaults"
        case .widener:
            return "Reset Widener tab to defaults"
        case .limiter:
            return "Reset Limiter tab to defaults"
        }
    }
}

enum RDSTab: String, CaseIterable, Identifiable {
    case program = "Program"
    case radiotext = "Radiotext"
    case longPS = "Long PS"
    case flags = "Flags"
    case carrier = "Carrier"

    var id: String { rawValue }

    var resetButtonTitle: String {
        switch self {
        case .program:
            return "Reset Program Tab"
        case .radiotext:
            return "Reset Radiotext Tab"
        case .longPS:
            return "Reset Long PS Tab"
        case .flags:
            return "Reset Flags Tab"
        case .carrier:
            return "Reset Carrier Tab"
        }
    }

    var resetStatusText: String {
        switch self {
        case .program:
            return "Reset RDS program tab to defaults"
        case .radiotext:
            return "Reset RDS radiotext tab to defaults"
        case .longPS:
            return "Reset RDS long PS tab to defaults"
        case .flags:
            return "Reset RDS flags tab to defaults"
        case .carrier:
            return "Reset RDS carrier tab to defaults"
        }
    }
}

struct PresetChoice: Identifiable {
    let id: String
    let title: String
}

enum MonitoringBufferHealth: String {
    case ok = "OK"
    case warn = "Warn"
    case bad = "Dropouts"
}

struct MonitoringStreamHealth {
    var isRunning: Bool = false
    var inputName: String = "None"
    var renderHz: Int = 0
    var inputHz: Int = 0
    var blockFrames: Int = 0
    var ringFrames: Int = 0
    var ringCapacity: Int = 0
    var overflowsRecent: Int = 0
    var underflowsRecent: Int = 0
    var overflowsTotal: Int = 0
    var underflowsTotal: Int = 0

    static let stopped = MonitoringStreamHealth()

    var ringFill: Double {
        guard ringCapacity > 0 else { return 0.0 }
        return Double(ringFrames) / Double(ringCapacity)
    }

    var dropoutsRecent: Int {
        overflowsRecent + underflowsRecent
    }

    var bufferHealth: MonitoringBufferHealth {
        guard isRunning else { return .ok }
        if dropoutsRecent >= 3 { return .bad }
        if dropoutsRecent > 0 { return .warn }
        if ringCapacity > 0 && ringFill < 0.15 { return .warn }
        return .ok
    }

    var rateSummary: String {
        if inputHz > 0, renderHz > 0, inputHz != renderHz {
            return "\(inputHz) -> \(renderHz) Hz"
        }
        let effective = max(renderHz, inputHz)
        return effective > 0 ? "\(effective) Hz" : "n/a"
    }

    var bufferSummary: String {
        guard isRunning else { return "n/a" }
        switch bufferHealth {
        case .ok:
            return MonitoringBufferHealth.ok.rawValue
        case .warn:
            return MonitoringBufferHealth.warn.rawValue
        case .bad:
            return "\(MonitoringBufferHealth.bad.rawValue) (\(dropoutsRecent))"
        }
    }

    var estimatedDelayMS: Double? {
        guard isRunning, renderHz > 0 else { return nil }
        let renderBlockMS = (Double(max(1, blockFrames)) / Double(renderHz)) * 1000.0
        if inputHz > 0 {
            return (Double(max(0, ringFrames)) / Double(inputHz)) * 1000.0 + renderBlockMS
        }
        return renderBlockMS
    }
}

private struct PeakHoldState {
    var value: Float = 0.0
    var holdRemaining: Double = 0.0
}

private struct AudioPeakHoldState {
    var db: Float = -120.0
    var holdRemaining: Double = 0.0
}

private final class MPXSpectrumAnalyzer: @unchecked Sendable {
    private var fftSetup: FFTSetup?
    private var fftLog2: vDSP_Length = 0
    private var window: [Float] = []
    private var signal: [Float] = []
    private var windowed: [Float] = []
    private var real: [Float] = []
    private var imag: [Float] = []
    private var magnitudesSq: [Float] = []
    private var spectrumDB: [Float] = []
    private var mapped: [Float] = []

    deinit {
        if let fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }

    func compute(
        samples: [Float],
        sampleRate: Double,
        displayBins: Int,
        maxDisplayHz: Double
    ) -> (dbBins: [Float], maxHz: Double, nyquistHz: Double) {
        let safeBins = max(64, displayBins)
        let nyquist = max(1_000.0, sampleRate * 0.5)
        let maxHz = max(1_000.0, maxDisplayHz)
        guard samples.count >= 256 else {
            return (Array(repeating: -100.0, count: safeBins), maxHz, nyquist)
        }

        let maxFFTSize = min(samples.count, 8192)
        let log2n = Int(floor(log2(Double(maxFFTSize))))
        let n = max(256, 1 << log2n)
        prepareBuffers(fftSize: n, displayBins: safeBins)

        signal.withUnsafeMutableBufferPointer { buffer in
            samples.suffix(n).withUnsafeBufferPointer { source in
                buffer.baseAddress?.update(from: source.baseAddress!, count: n)
            }
        }

        var mean: Float = 0.0
        vDSP_meanv(signal, 1, &mean, vDSP_Length(n))
        var negMean = -mean
        vDSP_vsadd(signal, 1, &negMean, &signal, 1, vDSP_Length(n))
        vDSP_vmul(signal, 1, window, 1, &windowed, 1, vDSP_Length(n))

        guard let fftSetup else {
            return (Array(repeating: -100.0, count: safeBins), maxHz, nyquist)
        }

        real.withUnsafeMutableBufferPointer { realBP in
            imag.withUnsafeMutableBufferPointer { imagBP in
                var split = DSPSplitComplex(realp: realBP.baseAddress!, imagp: imagBP.baseAddress!)
                windowed.withUnsafeBufferPointer { src in
                    src.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { complexSrc in
                        vDSP_ctoz(complexSrc, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, fftLog2, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudesSq, 1, vDSP_Length(n / 2))
            }
        }

        let invN = 1.0 / Float(n)
        if !magnitudesSq.isEmpty {
            let dcAmp = sqrtf(max(0.0, magnitudesSq[0])) * invN
            spectrumDB[0] = max(-100.0, min(0.0, 20.0 * log10f(max(1e-9, dcAmp))))
        }
        if magnitudesSq.count > 1 {
            for k in 1..<magnitudesSq.count {
                let amp = (2.0 * sqrtf(max(0.0, magnitudesSq[k]))) * invN
                spectrumDB[k] = max(-100.0, min(0.0, 20.0 * log10f(max(1e-9, amp))))
            }
        }

        let sourceCount = max(1, spectrumDB.count)
        for i in 0..<safeBins {
            let ratio = safeBins > 1 ? (Double(i) / Double(safeBins - 1)) : 0.0
            let freq = ratio * maxHz
            if freq > nyquist {
                mapped[i] = -100.0
                continue
            }
            let srcPos = (freq / nyquist) * Double(sourceCount - 1)
            let i0 = max(0, min(sourceCount - 1, Int(srcPos.rounded(.down))))
            let i1 = max(0, min(sourceCount - 1, i0 + 1))
            let frac = Float(srcPos - Double(i0))
            let a = spectrumDB[i0]
            let b = spectrumDB[i1]
            mapped[i] = a + ((b - a) * frac)
        }
        return (mapped, maxHz, nyquist)
    }

    private func prepareBuffers(fftSize: Int, displayBins: Int) {
        let requiredLog2 = vDSP_Length(log2(Double(fftSize)))
        if fftLog2 != requiredLog2 || fftSetup == nil {
            if let fftSetup {
                vDSP_destroy_fftsetup(fftSetup)
            }
            fftSetup = vDSP_create_fftsetup(requiredLog2, FFTRadix(kFFTRadix2))
            fftLog2 = requiredLog2
        }

        if window.count != fftSize {
            window = Array(repeating: 0.0, count: fftSize)
            signal = Array(repeating: 0.0, count: fftSize)
            windowed = Array(repeating: 0.0, count: fftSize)
            vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        }

        let halfSize = fftSize / 2
        if real.count != halfSize {
            real = Array(repeating: 0.0, count: halfSize)
            imag = Array(repeating: 0.0, count: halfSize)
            magnitudesSq = Array(repeating: 0.0, count: halfSize)
            spectrumDB = Array(repeating: -100.0, count: halfSize)
        }

        if mapped.count != displayBins {
            mapped = Array(repeating: -100.0, count: displayBins)
        }
    }
}

private struct OrbassPreset {
    let id: String
    let title: String
    let enabled: Bool
    let amount: Double
    let freqHz: Double
    let harmonics: Double
    let drive: Double
    let density: Double
    let subharmonicsEnabled: Bool
    let subharmonicsAmount: Double
}

private struct MultibandPreset {
    let id: String
    let title: String
    let mode: Int
    let lowHz: Double?
    let highHz: Double?
    let x1Hz: Double?
    let x2Hz: Double?
    let x3Hz: Double?
    let x4Hz: Double?
    let lowThresholdDB: Double
    let lowRatio: Double
    let lowAttackMS: Double
    let lowReleaseMS: Double
    let midThresholdDB: Double
    let midRatio: Double
    let midAttackMS: Double
    let midReleaseMS: Double
    let highThresholdDB: Double
    let highRatio: Double
    let highAttackMS: Double
    let highReleaseMS: Double
    let kneeDB: Double
    let linkStrength: Double
    let releaseProgramDependent: Bool
}

private struct FinalStagePreset {
    let id: String
    let title: String
    let agcEnabled: Bool
    let agcTargetDB: Double
    let agcAttackMS: Double
    let agcReleaseMS: Double
    let agcMaxGainDB: Double
    let agcMinGainDB: Double
    let finalDriveDB: Double
    let compositeLimiterEnabled: Bool
}

enum MultibandPresetIntensity: String, CaseIterable, Identifiable {
    case light
    case normal
    case heavy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Light"
        case .normal: return "Normal"
        case .heavy: return "Heavy"
        }
    }

    var thresholdDbOffset: Double {
        switch self {
        case .light: return 1.5
        case .normal: return 0.0
        case .heavy: return -1.5
        }
    }

    var ratioMul: Double {
        switch self {
        case .light: return 0.9
        case .normal: return 1.0
        case .heavy: return 1.12
        }
    }

    var attackMul: Double {
        switch self {
        case .light: return 1.2
        case .normal: return 1.0
        case .heavy: return 0.88
        }
    }

    var releaseMul: Double {
        switch self {
        case .light: return 1.15
        case .normal: return 1.0
        case .heavy: return 0.9
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSWindowDelegate {
    private let configPath: String
    private let runSeconds: Double?
    private var window: NSWindow?
    private var model: StereoFoolViewModel?
    private var scopesWindow: NSWindow?
    private var spectrumWindow: NSWindow?
    private var levelsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var helpWindow: NSWindow?
    private var settingsWindow: NSWindow?

    init(configPath: String, runSeconds: Double?) {
        self.configPath = configPath
        self.runSeconds = runSeconds
    }

    private func restoreFrame(for window: NSWindow, autosaveName: String) {
        window.setFrameAutosaveName(autosaveName)
        if !window.setFrameUsingName(autosaveName) {
            window.center()
        }
    }

    private func revealWindow(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender == window {
            sender.orderOut(nil)
            return false
        } else if sender == scopesWindow {
            sender.orderOut(nil)
            return false
        } else if sender == spectrumWindow {
            model?.spectrumWindowVisible = false
            sender.orderOut(nil)
            return false
        } else if sender == levelsWindow {
            sender.orderOut(nil)
            return false
        } else if sender == aboutWindow {
            sender.orderOut(nil)
            return false
        } else if sender == helpWindow {
            sender.orderOut(nil)
            return false
        } else if sender == settingsWindow {
            sender.orderOut(nil)
            return false
        }
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        showMainWindow()
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = makeStereoFoolAppIcon()
        NSApp.activate(ignoringOtherApps: true)
        
        let vm = StereoFoolViewModel(configPath: configPath)
        model = vm
        setupMainMenu()

        let root = RootView(model: vm)
        let host = NSHostingView(rootView: root)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.center()
        w.title = "StereoFool"
        w.titleVisibility = .visible
        w.minSize = NSSize(width: 900, height: 620)
        w.delegate = self
        restoreFrame(for: w, autosaveName: kMainWindowAutosaveName)
        w.contentView = host
        w.makeKeyAndOrderFront(nil)
        window = w

        vm.startMonitoringTimer()
        if vm.autoStartEnabled {
            vm.startOrStopTransport(forceStart: true)
        }

        if let secs = runSeconds {
            DispatchQueue.main.asyncAfter(deadline: .now() + secs) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.shutdown()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(applyPendingChanges) {
            menuItem.title = model?.runtimeApplyButtonTitle ?? "Apply Restart"
            return model?.runtimeApplyPending ?? false
        }
        return true
    }

    private func setupMainMenu() {
        let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "StereoFool"
        let mainMenu = NSMenu()

        // App Menu (unchanged)
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: appName)
        let aboutItem = appMenu.addItem(
            withTitle: "About \(appName)", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(NSMenuItem.separator())
        let settingsItem = appMenu.addItem(
            withTitle: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(withTitle: "Services", action: nil, keyEquivalent: "").submenu = NSMenu(
            title: "Services")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h")
        let hideOthersItem = appMenu.addItem(
            withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(
            withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // File Menu
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "File")
        let openItem = fileMenu.addItem(withTitle: "Open...", action: #selector(openConfig), keyEquivalent: "o")
        openItem.target = self
        let saveItem = fileMenu.addItem(withTitle: "Save", action: #selector(saveConfig), keyEquivalent: "s")
        saveItem.target = self
        let saveAsItem = fileMenu.addItem(withTitle: "Save As...", action: #selector(saveConfigAs), keyEquivalent: "S")
        saveAsItem.target = self
        saveAsItem.keyEquivalentModifierMask = [.command, .shift]
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        // Control Menu
        let transportItem = NSMenuItem(title: "Control", action: nil, keyEquivalent: "")
        let transportMenu = NSMenu(title: "Control")

        let startStopItem = transportMenu.addItem(
            withTitle: "Start/Stop", action: #selector(toggleTransport), keyEquivalent: "t"
        )
        startStopItem.target = self
        startStopItem.keyEquivalentModifierMask = [.command]
        let bypassItem = transportMenu.addItem(
            withTitle: "Bypass", action: #selector(toggleBypass), keyEquivalent: "b")
        bypassItem.target = self
        let resetPeaksItem = transportMenu.addItem(
            withTitle: "Reset Peaks", action: #selector(resetPeaks), keyEquivalent: "r")
        resetPeaksItem.target = self
        transportMenu.addItem(NSMenuItem.separator())
        let applyItem = transportMenu.addItem(
            withTitle: "Apply Restart", action: #selector(applyPendingChanges), keyEquivalent: "A")
        applyItem.target = self
        applyItem.keyEquivalentModifierMask = [.command, .shift]

        transportItem.submenu = transportMenu
        mainMenu.addItem(transportItem)

        // Window Menu
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "Window")
        
        let mainWindowItem = windowMenu.addItem(withTitle: "Main", action: #selector(showMainWindow), keyEquivalent: "1")
        mainWindowItem.target = self
        let spectrumItem = windowMenu.addItem(withTitle: "Spectrum", action: #selector(showSpectrumWindow), keyEquivalent: "8")
        spectrumItem.target = self
        let levelsItem = windowMenu.addItem(withTitle: "Levels", action: #selector(showLevelsWindow), keyEquivalent: "9")
        levelsItem.target = self
        let scopesItem = windowMenu.addItem(withTitle: "Scopes", action: #selector(showScopesWindow), keyEquivalent: "0")
        scopesItem.target = self
        
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        let helpItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        let helpMenu = NSMenu(title: "Help")
        
        let openHelp = NSMenuItem(title: "StereoFool Help", action: #selector(showHelp), keyEquivalent: "/")
        openHelp.target = self
        openHelp.keyEquivalentModifierMask = [.command, .shift]
        helpMenu.addItem(openHelp)
        
        helpMenu.addItem(NSMenuItem.separator())
        
        let docs = NSMenuItem(title: "Online Documentation", action: #selector(openDocs), keyEquivalent: "")
        docs.target = self
        docs.isEnabled = true
        helpMenu.addItem(docs)
        
        helpItem.submenu = helpMenu
        mainMenu.addItem(helpItem)
        
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func showAbout() {
        if let existing = aboutWindow {
            revealWindow(existing)
            return
        }
        let aboutView = AboutSectionView()
        let hostingController = NSHostingController(rootView: aboutView)
        let w = NSWindow(contentViewController: hostingController)
        w.title = "About StereoFool"
        w.styleMask = [.titled, .closable]
        w.setContentSize(NSSize(width: 450, height: 500))
        w.isReleasedWhenClosed = false
        w.delegate = self
        restoreFrame(for: w, autosaveName: kAboutWindowAutosaveName)
        w.makeKeyAndOrderFront(nil)
        aboutWindow = w
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func showHelp() {
        if let existing = helpWindow {
            revealWindow(existing)
            return
        }
        let helpView = HelpWindowView()
        let hostingController = NSHostingController(rootView: helpView)
        let w = NSWindow(contentViewController: hostingController)
        w.title = "StereoFool Help"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.setContentSize(NSSize(width: 560, height: 560))
        w.minSize = NSSize(width: 520, height: 420)
        w.isReleasedWhenClosed = false
        w.delegate = self
        restoreFrame(for: w, autosaveName: kHelpWindowAutosaveName)
        w.makeKeyAndOrderFront(nil)
        helpWindow = w
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func openDocs() {
        NSWorkspace.shared.open(URL(string: "https://github.com/bkram/StereoFool")!)
    }

    @objc private func showSettings() {
        if let existing = settingsWindow {
            revealWindow(existing)
            return
        }
        guard let vm = model else { return }
        let settingsView = SettingsWindowView(model: vm)
        let hostingController = NSHostingController(rootView: settingsView)
        let w = NSWindow(contentViewController: hostingController)
        w.title = "Settings"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.toolbarStyle = .unified
        w.setContentSize(NSSize(width: 780, height: 620))
        w.minSize = NSSize(width: 700, height: 520)
        w.isReleasedWhenClosed = false
        w.delegate = self
        restoreFrame(for: w, autosaveName: kSettingsWindowAutosaveName)
        w.makeKeyAndOrderFront(nil)
        settingsWindow = w
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func toggleTransport() {
        model?.startOrStopTransport()
    }

    @objc private func toggleBypass() {
        model?.toggleBypass()
    }

    @objc private func resetPeaks() {
        model?.resetPeaks()
    }

    @objc private func saveConfig() {
        model?.saveCurrentConfig()
    }

    @objc private func applyPendingChanges() {
        model?.applyPendingRuntimeChanges()
    }

    @objc private func showMainWindow() {
        if let existing = window {
            revealWindow(existing)
            return
        }
        guard let vm = model else { return }
        let root = RootView(model: vm)
        let host = NSHostingView(rootView: root)
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.center()
        w.title = "StereoFool"
        w.titleVisibility = .visible
        w.minSize = NSSize(width: 900, height: 620)
        w.delegate = self
        restoreFrame(for: w, autosaveName: kMainWindowAutosaveName)
        w.contentView = host
        w.makeKeyAndOrderFront(nil)
        window = w
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func showScopesWindow() {
        if let existing = scopesWindow {
            revealWindow(existing)
            return
        }
        guard let vm = model else { return }
        let scopesView = ScopesOnlyView(model: vm)
        let hostingController = NSHostingController(rootView: scopesView)
        let w = NSWindow(contentViewController: hostingController)
        w.title = "Scopes"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.setContentSize(NSSize(width: kWindowWidth, height: kWindowHeight))
        w.minSize = NSSize(width: kWindowMinWidth, height: kWindowMinHeight)
        w.isReleasedWhenClosed = false
        w.delegate = self
        restoreFrame(for: w, autosaveName: kScopesWindowAutosaveName)
        w.makeKeyAndOrderFront(nil)
        scopesWindow = w
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func showSpectrumWindow() {
        if let existing = spectrumWindow {
            revealWindow(existing)
            model?.spectrumWindowVisible = true
            return
        }
        guard let vm = model else { return }
        let spectrumView = SpectrumOnlyView(model: vm)
        let hostingController = NSHostingController(rootView: spectrumView)
        let w = NSWindow(contentViewController: hostingController)
        w.title = "Spectrum"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.setContentSize(NSSize(width: kWindowWidth, height: kWindowHeight))
        w.minSize = NSSize(width: kWindowMinWidth, height: kWindowMinHeight)
        w.isReleasedWhenClosed = false
        w.delegate = self
        restoreFrame(for: w, autosaveName: kSpectrumWindowAutosaveName)
        w.makeKeyAndOrderFront(nil)
        spectrumWindow = w
        model?.spectrumWindowVisible = true
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func showLevelsWindow() {
        if let existing = levelsWindow {
            revealWindow(existing)
            return
        }
        guard let vm = model else { return }
        let levelsView = LevelsOnlyView(model: vm)
        let hostingController = NSHostingController(rootView: levelsView)
        let w = NSWindow(contentViewController: hostingController)
        w.title = "Levels"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.setContentSize(NSSize(width: kLevelsWindowWidth, height: kLevelsWindowHeight))
        w.minSize = NSSize(width: kLevelsWindowMinWidth, height: kLevelsWindowMinHeight)
        w.isReleasedWhenClosed = false
        w.delegate = self
        restoreFrame(for: w, autosaveName: kLevelsWindowAutosaveName)
        w.makeKeyAndOrderFront(nil)
        levelsWindow = w
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func openConfig() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [UTType(filenameExtension: "ini")!]
        openPanel.message = "Choose a configuration file to open"
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowsMultipleSelection = false

        openPanel.begin { [weak self] response in
            guard response == .OK, let url = openPanel.url else { return }
            self?.model?.loadConfigFromFile(url.path)
        }
    }

    @objc private func saveConfigAs() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [UTType(filenameExtension: "ini")!]
        savePanel.message = "Save configuration as..."
        savePanel.nameFieldStringValue = "config.ini"

        savePanel.begin { [weak self] response in
            guard response == .OK, let url = savePanel.url else { return }
            self?.model?.saveConfigToFile(url.path)
        }
    }

}

@MainActor
final class StereoFoolViewModel: ObservableObject {
    private struct RuntimeSnapshot {
        var config: AppConfig
        var sourceMode: String
        var monitorEnabled: Bool
        var processingBypass: Bool
        var inputGainDB: Double
        var selectedInputUID: String
        var selectedOutputUID: String
        var selectedMonitorUID: String
    }

    private static let monitoringRefreshHz: Double = 30.0
    private static let meterAttackMS: Float = 18.0
    private static let meterReleaseMS: Float = 110.0
    private static let audioPeakMeterAttackMS: Float = 1.0
    private static let audioPeakMeterReleaseMS: Float = 180.0

    @Published var selectedSection: AppSection = .monitoring
    @Published var selectedProcessingTab: ProcessingTab = .core
    @Published var selectedRDSTab: RDSTab = .program
    @Published var statusText: String = "Idle"
    @Published var pendingRuntimeApply: Bool = false

    @Published var sourceMode: String
    @Published var monitorEnabled: Bool
    @Published var processingBypass: Bool
    @Published var inputGainDB: Double

    @Published var inputDevices: [AudioDevice] = []
    @Published var outputDevices: [AudioDevice] = []
    @Published var selectedInputUID: String = ""
    @Published var selectedOutputUID: String = ""
    @Published var selectedMonitorUID: String = ""

    @Published var isRunning: Bool = false
    @Published var isTransitioning: Bool = false
    @Published var runtimeText: String = "Not running"
    @Published var inputRingText: String = "Input ring: n/a"
    @Published var inputBufferValue: Double = 0.0
    @Published var inputBufferMax: Double = 1.0
    @Published var inputBufferWarning: Double = 0.7
    @Published var inputBufferCritical: Double = 0.9
    @Published var streamHealth: MonitoringStreamHealth = .stopped

    @Published var inputLLevel: Double = 0.0
    @Published var inputRLevel: Double = 0.0
    @Published var outputLevel: Double = 0.0
    @Published var modulationLevel: Double = 0.0
    @Published var inputLPeakHoldLevel: Double = 0.0
    @Published var inputRPeakHoldLevel: Double = 0.0
    @Published var outputPeakHoldLevel: Double = 0.0
    @Published var modulationPeakHoldLevel: Double = 0.0
    @Published var stickyPeaksEnabled: Bool = true
    @Published var meterPeakHoldSeconds: Double = 1.5
    @Published var meterPeakFallDBPerSecond: Double = 18.0

    @Published var inputLText: String = "-inf dBFS"
    @Published var inputRText: String = "-inf dBFS"
    @Published var outputText: String = "-inf dBFS"
    @Published var modulationText: String = "0.0 kHz"
    @Published var loudnessAvailable: Bool = false
    @Published var loudnessMomentaryText: String = "—"
    @Published var loudnessShortTermText: String = "—"
    @Published var loudnessIntegratedText: String = "—"
    @Published var loudnessStatusText: String = "Enable Monitor Output to measure decoded-program loudness."

    @Published var limiterStateText: String = "Off"
    @Published var limiterDetailText: String = "Drive 0.0 dB • GR 0.0 dB • Safe 0.0 dB • Peak -inf dBFS"
    @Published var compositeBudgetStateText: String = "Off"
    @Published var compositeCalibrationText: String = "Pilot 0.0% • RDS 0.0% • Audio -inf dBFS • Margin 0.0 dB"
    @Published var stereoImageText: String = "Corr +1.00 • Side 0.00x"
    @Published var agcStateText: String = "Off"
    @Published var agcDetailText: String = "Detector -inf dB • Gain 0.0 dB"
    @Published var multibandStateText: String = "Off"
    @Published var orbassStateText: String = "Off"
    @Published var widenerStateText: String = "Off"

    @Published var rdsPS: String = "-"
    @Published var rdsPI: String = "-"
    @Published var rdsPTY: String = "-"
    @Published var rdsPTYN: String = "-"
    @Published var rdsAID: String = "AID: OFF"
    @Published var rdsLongPS: String = "-"
    @Published var rdsRadiotext: String = "-"
    @Published var rdsNowPlayingStatus: String = "Now Playing: off"

    @Published var inputScope: [Float] = Array(repeating: 0.0, count: 128)
    @Published var outputScope: [Float] = Array(repeating: 0.0, count: 128)
    @Published var scopeTimebaseMS: Double = 10.0
    @Published var scopeAutoGainEnabled: Bool = true
    @Published var mpxSpectrumDB: [Float] = Array(repeating: -100.0, count: 640)
    @Published var mpxSpectrumMaxHz: Double = 92_000.0
    @Published var mpxSpectrumNyquistHz: Double = 0.0
    @Published var spectrumWindowVisible: Bool = false

    private let configPath: String
    private let nowPlayingState: NowPlayingState
    private let nowPlayingRunner: NowPlayingScriptRunner
    var config: AppConfig
    private var runningEngine: AudioOutputEngine?
    private var activeRuntimeSnapshot: RuntimeSnapshot?
    private var monitorTimer: Timer?
    private var lastMonitorRefreshTime: TimeInterval?
    private var engineStartReference: TimeInterval?

    private var vuInputL: Float = 0.0
    private var vuInputR: Float = 0.0
    private var vuOutput: Float = 0.0
    private var vuModulation: Float = 0.0
    private var peakHoldInputL = AudioPeakHoldState()
    private var peakHoldInputR = AudioPeakHoldState()
    private var peakHoldOutput = AudioPeakHoldState()
    private var peakHoldModulation = PeakHoldState()
    private var limiterGRPeakHoldDB: Float = 0.0
    private var limiterGRPeakHoldRemaining: Double = 0.0

    private var smoothedInputScope: [Float] = Array(repeating: 0.0, count: 128)
    private var smoothedOutputScope: [Float] = Array(repeating: 0.0, count: 128)
    private var inputScopeGain: Float = 1.0
    private var outputScopeGain: Float = 1.0
    private var overflowHistory: [(time: TimeInterval, overflows: UInt64, underflows: UInt64)] = []
    private var lastOverflowTotal: UInt64 = 0
    private var lastUnderflowTotal: UInt64 = 0
    private var pendingConfigSnapshot: AppConfig?
    private var configSaveInFlight: Bool = false
    private var configWatchFD: Int32 = -1
    private var configWatchSource: DispatchSourceFileSystemObject?
    private var configReloadWorkItem: DispatchWorkItem?
    private var ignoreConfigReloadUntil: TimeInterval = 0.0
    private var lastSpectrumRefreshTime: TimeInterval?
    private var spectrumUpdateInFlight: Bool = false
    private let spectrumQueue = DispatchQueue(label: "StereoFool.MPXSpectrum", qos: .userInitiated)
    private let spectrumAnalyzer = MPXSpectrumAnalyzer()

    init(configPath: String) {
        self.configPath = configPath
        let loadedConfig: AppConfig
        do {
            loadedConfig = try AppConfig.load(fromINI: configPath)
        } catch {
            loadedConfig = AppConfig()
            try? loadedConfig.save(toINI: configPath)
        }
        self.config = loadedConfig

        self.sourceMode = loadedConfig.sourceMode
        self.monitorEnabled = loadedConfig.monitorEnabled
        self.processingBypass = loadedConfig.processingBypass
        self.inputGainDB = loadedConfig.inputGainDB
        self.nowPlayingState = NowPlayingState()
        self.nowPlayingRunner = NowPlayingScriptRunner(state: self.nowPlayingState)
        self.nowPlayingRunner.setStatusHandler { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                self.rdsNowPlayingStatus = status
                self.refreshMonitoringSnapshot()
            }
        }

        refreshDevices()
        nowPlayingRunner.updateConfig(loadedConfig)
        startConfigWatcher()
        refreshMonitoringSnapshot()
    }

    var autoStartEnabled: Bool { config.rdsAutoStart }

    var isBusy: Bool { isTransitioning }

    var configFilePath: String { configPath }

    var runtimeApplyPending: Bool { isRunning && pendingRuntimeApply }

    var runtimeApplyButtonTitle: String { "Apply Restart" }

    var runtimeApplyHintText: String {
        "Pending changes affect engine, routing, or encoder structure and require a restart to take effect."
    }

    var restartRequiredSettingsListText: String { kRestartRequiredSettingsListText }

    var ptyChoices: [(Int, String)] {
        Self.ptyNames.enumerated().map { ($0.offset, $0.element) }
    }

    var orbassPresetChoices: [PresetChoice] {
        Self.orbassPresets.map { PresetChoice(id: $0.id, title: $0.title) }
    }

    var multibandPresetChoices: [PresetChoice] {
        Self.multibandPresets.map { PresetChoice(id: $0.id, title: $0.title) }
    }

    var finalStagePresetChoices: [PresetChoice] {
        Self.finalStagePresets.map { PresetChoice(id: $0.id, title: $0.title) }
    }

    var rdsRows: [(String, String)] {
        [
            ("PS", rdsPS),
            ("PI", rdsPI),
            ("PTY", rdsPTY),
            ("PTYN", rdsPTYN),
            ("RT+ App ID", rdsAID),
            ("Long PS", rdsLongPS),
            ("Radiotext", rdsRadiotext),
            ("Now Playing", rdsNowPlayingStatus.replacingOccurrences(of: "Now Playing: ", with: "")),
        ]
    }

    func startMonitoringTimer() {
        monitorTimer?.invalidate()
        let timer = Timer(timeInterval: (1.0 / Self.monitoringRefreshHz), repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshMonitoringSnapshot()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        monitorTimer = timer
        timer.fire()
    }

    func shutdown() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        lastMonitorRefreshTime = nil
        nowPlayingRunner.stop()
        stopConfigWatcher()
        stopEngineIfNeeded()
    }

    func refreshDevices() {
        do {
            let devices = try AudioDevices.list()
            inputDevices = devices.filter { $0.hasInput }
            outputDevices = devices.filter { $0.hasOutput }
            selectedInputUID = selectUID(preferred: config.inputDeviceUID, from: inputDevices)
            selectedOutputUID = selectUID(preferred: config.outputDeviceUID, from: outputDevices)
            selectedMonitorUID = selectUID(preferred: config.monitorDeviceUID, from: outputDevices)
        } catch {
            statusText = "Device scan failed: \(error)"
            inputDevices = []
            outputDevices = []
            selectedInputUID = ""
            selectedOutputUID = ""
            selectedMonitorUID = ""
        }
    }

    func persistBasicConfig() {
        config.sourceMode = sourceMode
        config.monitorEnabled = monitorEnabled
        config.processingBypass = processingBypass
        config.inputGainDB = inputGainDB
        config.inputDeviceUID = selectedInputUID.isEmpty ? nil : selectedInputUID
        config.outputDeviceUID = selectedOutputUID.isEmpty ? nil : selectedOutputUID
        config.monitorDeviceUID = selectedMonitorUID.isEmpty ? nil : selectedMonitorUID
        saveConfig(restartRequired: isRunning)
    }

    func applyPendingRuntimeChanges() {
        guard runtimeApplyPending else { return }
        pendingRuntimeApply = false
        restartEngineWithStatus("Config changes")
    }

    func value<T>(for keyPath: KeyPath<AppConfig, T>) -> T {
        config[keyPath: keyPath]
    }

    func setConfigValue<T>(
        _ keyPath: WritableKeyPath<AppConfig, T>,
        _ value: T,
        runtimeDisposition: RuntimeChangeDisposition = .restart
    ) {
        publishConfigChange()
        config[keyPath: keyPath] = value
        saveConfig(restartRequired: runtimeDisposition == .restart)
        if runtimeDisposition == .live {
            applyLiveRuntimeConfigIfRunning()
        }
        updateNowPlayingRunner()
    }

    func configBinding<T>(
        _ keyPath: WritableKeyPath<AppConfig, T>,
        runtimeDisposition: RuntimeChangeDisposition = .restart
    ) -> Binding<T> {
        Binding(
            get: { self.config[keyPath: keyPath] },
            set: { self.setConfigValue(keyPath, $0, runtimeDisposition: runtimeDisposition) }
        )
    }

    func ptyBinding() -> Binding<Int> {
        Binding(
            get: { self.config.rdsPTY },
            set: { self.setConfigValue(\.rdsPTY, max(0, min(31, $0)), runtimeDisposition: .restart) }
        )
    }

    func piBinding() -> Binding<String> {
        Binding(
            get: { self.config.rdsPI },
            set: {
                self.setConfigValue(\.rdsPI, Self.sanitizeHex($0, width: 4), runtimeDisposition: .restart)
            }
        )
    }

    func hexByteBinding(_ keyPath: WritableKeyPath<AppConfig, String>) -> Binding<String> {
        Binding(
            get: { self.config[keyPath: keyPath] },
            set: {
                self.setConfigValue(keyPath, Self.sanitizeHex($0, width: 2), runtimeDisposition: .restart)
            }
        )
    }

    func oddTapBinding() -> Binding<Int> {
        Binding(
            get: { self.config.rdsGaussianTaps },
            set: { raw in
                let clamped = max(9, min(401, raw))
                let odd =
                    (clamped % 2 == 0) ? (clamped + 1 <= 401 ? clamped + 1 : clamped - 1) : clamped
                self.setConfigValue(\.rdsGaussianTaps, odd, runtimeDisposition: .restart)
            }
        )
    }

    func applyOrbassPreset(id: String) {
        guard let preset = Self.orbassPresets.first(where: { $0.id == id }) else { return }
        publishConfigChange()
        config.orbassEnabled = preset.enabled
        config.orbassPresetID = id
        config.orbassAmount = preset.amount
        config.orbassFreqHz = preset.freqHz
        config.orbassHarmonics = preset.harmonics
        config.orbassDrive = preset.drive
        config.orbassDensity = preset.density
        config.orbassSubharmonicsEnabled = preset.subharmonicsEnabled
        config.orbassSubharmonicsAmount = preset.subharmonicsAmount
        saveConfig(restartRequired: false)
        applyLiveRuntimeConfigIfRunning()
        statusText =
            isRunning
            ? "Loaded Orbass preset \(preset.title) live."
            : "Loaded Orbass preset \(preset.title)."
    }

    func applyMultibandPreset(id: String, intensity: MultibandPresetIntensity) {
        guard let preset = Self.multibandPresets.first(where: { $0.id == id }) else { return }
        publishConfigChange()

        config.multibandEnabled = true
        config.multibandMode = preset.mode
        config.multibandPresetID = id
        config.multibandIntensity = intensity.rawValue

        if let lowHz = preset.lowHz {
            config.multibandLowHz = lowHz
            config.multibandX1Hz = lowHz
        }
        if let highHz = preset.highHz {
            config.multibandHighHz = highHz
            config.multibandX2Hz = highHz
        }
        if let x1Hz = preset.x1Hz {
            config.multibandX1Hz = x1Hz
        }
        if let x2Hz = preset.x2Hz {
            config.multibandX2Hz = x2Hz
        }
        if let x3Hz = preset.x3Hz {
            config.multibandX3Hz = x3Hz
        }
        if let x4Hz = preset.x4Hz {
            config.multibandX4Hz = x4Hz
        }

        config.multibandLowThresholdDB = Self.clamp(
            preset.lowThresholdDB + intensity.thresholdDbOffset,
            min: -36.0,
            max: -6.0
        )
        config.multibandMidThresholdDB = Self.clamp(
            preset.midThresholdDB + intensity.thresholdDbOffset,
            min: -36.0,
            max: -6.0
        )
        config.multibandHighThresholdDB = Self.clamp(
            preset.highThresholdDB + intensity.thresholdDbOffset,
            min: -36.0,
            max: -6.0
        )

        config.multibandLowRatio = Self.clamp(
            preset.lowRatio * intensity.ratioMul, min: 1.0, max: 4.0)
        config.multibandMidRatio = Self.clamp(
            preset.midRatio * intensity.ratioMul, min: 1.0, max: 4.0)
        config.multibandHighRatio = Self.clamp(
            preset.highRatio * intensity.ratioMul, min: 1.0, max: 4.0)

        config.multibandLowAttackMS = Self.clamp(
            preset.lowAttackMS * intensity.attackMul, min: 1.0, max: 200.0)
        config.multibandMidAttackMS = Self.clamp(
            preset.midAttackMS * intensity.attackMul, min: 1.0, max: 200.0)
        config.multibandHighAttackMS = Self.clamp(
            preset.highAttackMS * intensity.attackMul, min: 1.0, max: 200.0)

        config.multibandLowReleaseMS = Self.clamp(
            preset.lowReleaseMS * intensity.releaseMul, min: 50.0, max: 1000.0)
        config.multibandMidReleaseMS = Self.clamp(
            preset.midReleaseMS * intensity.releaseMul, min: 50.0, max: 1000.0)
        config.multibandHighReleaseMS = Self.clamp(
            preset.highReleaseMS * intensity.releaseMul, min: 50.0, max: 1000.0)

        config.multibandKneeDB = preset.kneeDB
        config.multibandLinkStrength = preset.linkStrength
        config.multibandReleaseProgramDependent = preset.releaseProgramDependent

        saveConfig(restartRequired: false)
        applyLiveRuntimeConfigIfRunning()
        statusText =
            isRunning
            ? "Loaded Multiband preset \(preset.title) (\(intensity.title)) live."
            : "Loaded Multiband preset \(preset.title) (\(intensity.title))."
    }

    func applyFinalStagePreset(id: String) {
        guard let preset = Self.finalStagePresets.first(where: { $0.id == id }) else { return }
        publishConfigChange()
        config.finalStagePresetID = id
        config.widebandAGCEnabled = preset.agcEnabled
        config.widebandAGCTargetDB = preset.agcTargetDB
        config.widebandAGCAttackMS = preset.agcAttackMS
        config.widebandAGCReleaseMS = preset.agcReleaseMS
        config.widebandAGCMaxGainDB = preset.agcMaxGainDB
        config.widebandAGCMinGainDB = preset.agcMinGainDB
        config.finalDriveDB = preset.finalDriveDB
        config.compositeLimiterEnabled = preset.compositeLimiterEnabled
        saveConfig(restartRequired: false)
        applyLiveRuntimeConfigIfRunning()
        statusText =
            isRunning
            ? "Loaded final-stage preset \(preset.title) live."
            : "Loaded final-stage preset \(preset.title)."
    }

    func revealConfigInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: configPath)])
    }

    func reloadConfigFromDisk() {
        do {
            applyLoadedConfig(try AppConfig.load(fromINI: configPath), origin: .manual)
        } catch {
            statusText = "Config reload failed: \(error)"
        }
    }

    func resetToDefaults() {
        let savedSourceMode = sourceMode
        do {
            var defaults = AppConfig()
            defaults.sourceMode = savedSourceMode
            defaults.inputDeviceUID = selectedInputUID.isEmpty ? nil : selectedInputUID
            defaults.outputDeviceUID = selectedOutputUID.isEmpty ? nil : selectedOutputUID
            defaults.monitorEnabled = monitorEnabled
            defaults.monitorDeviceUID = selectedMonitorUID.isEmpty ? nil : selectedMonitorUID
            try defaults.save(toINI: configPath)
            config = defaults
            sourceMode = config.sourceMode
            processingBypass = config.processingBypass
            inputGainDB = config.inputGainDB
            updateNowPlayingRunner()
            applyPendingRuntimeChanges()
            statusText = "Reset to defaults"
        } catch {
            statusText = "Reset failed: \(error)"
        }
    }

    func resetCurrentProcessingTabToDefaults() {
        publishConfigChange()
        let defaults = AppConfig()

        switch selectedProcessingTab {
        case .core:
            processingBypass = defaults.processingBypass
            inputGainDB = defaults.inputGainDB
            config.processingBypass = defaults.processingBypass
            config.inputGainDB = defaults.inputGainDB
            config.outputGainDB = defaults.outputGainDB
            config.monoMode = defaults.monoMode
            config.preemphasisUS = defaults.preemphasisUS
            config.hpfHz = defaults.hpfHz
            config.hfTrimDB = defaults.hfTrimDB
            config.hfTrimHz = defaults.hfTrimHz
            config.programLowpassHz = defaults.programLowpassHz
        case .agc:
            config.widebandAGCEnabled = defaults.widebandAGCEnabled
            config.widebandAGCTargetDB = defaults.widebandAGCTargetDB
            config.widebandAGCAttackMS = defaults.widebandAGCAttackMS
            config.widebandAGCReleaseMS = defaults.widebandAGCReleaseMS
            config.widebandAGCMaxGainDB = defaults.widebandAGCMaxGainDB
            config.widebandAGCMinGainDB = defaults.widebandAGCMinGainDB
        case .orbass:
            config.orbassEnabled = defaults.orbassEnabled
            config.orbassPresetID = defaults.orbassPresetID
            config.orbassAmount = defaults.orbassAmount
            config.orbassFreqHz = defaults.orbassFreqHz
            config.orbassHarmonics = defaults.orbassHarmonics
            config.orbassDrive = defaults.orbassDrive
            config.orbassDensity = defaults.orbassDensity
            config.orbassSubharmonicsEnabled = defaults.orbassSubharmonicsEnabled
            config.orbassSubharmonicsAmount = defaults.orbassSubharmonicsAmount
        case .multiband:
            config.multibandEnabled = defaults.multibandEnabled
            config.multibandMode = defaults.multibandMode
            config.multibandPresetID = defaults.multibandPresetID
            config.multibandIntensity = defaults.multibandIntensity
            config.multibandX1Hz = defaults.multibandX1Hz
            config.multibandX2Hz = defaults.multibandX2Hz
            config.multibandX3Hz = defaults.multibandX3Hz
            config.multibandX4Hz = defaults.multibandX4Hz
            config.multibandLowThresholdDB = defaults.multibandLowThresholdDB
            config.multibandMidThresholdDB = defaults.multibandMidThresholdDB
            config.multibandHighThresholdDB = defaults.multibandHighThresholdDB
            config.multibandLowRatio = defaults.multibandLowRatio
            config.multibandMidRatio = defaults.multibandMidRatio
            config.multibandHighRatio = defaults.multibandHighRatio
            config.multibandLowAttackMS = defaults.multibandLowAttackMS
            config.multibandMidAttackMS = defaults.multibandMidAttackMS
            config.multibandHighAttackMS = defaults.multibandHighAttackMS
            config.multibandLowReleaseMS = defaults.multibandLowReleaseMS
            config.multibandMidReleaseMS = defaults.multibandMidReleaseMS
            config.multibandHighReleaseMS = defaults.multibandHighReleaseMS
            config.multibandKneeDB = defaults.multibandKneeDB
            config.multibandLinkStrength = defaults.multibandLinkStrength
            config.multibandReleaseProgramDependent = defaults.multibandReleaseProgramDependent
            config.multibandMakeupDB = defaults.multibandMakeupDB
        case .widener:
            config.stereoWidenEnabled = defaults.stereoWidenEnabled
            config.monoBassEnabled = defaults.monoBassEnabled
            config.monoBassFreqHz = defaults.monoBassFreqHz
            config.stereoWidenWidth = defaults.stereoWidenWidth
            config.stereoWidenCenter = defaults.stereoWidenCenter
            config.stereoWidenMix = defaults.stereoWidenMix
        case .limiter:
            config.finalStagePresetID = defaults.finalStagePresetID
            config.compositeLimiterEnabled = defaults.compositeLimiterEnabled
            config.finalDriveDB = defaults.finalDriveDB
            config.mpxDeviationKHz = defaults.mpxDeviationKHz
        }

        let runtimeDisposition: RuntimeChangeDisposition
        switch selectedProcessingTab {
        case .core:
            runtimeDisposition = .restart
        case .agc, .orbass, .multiband, .widener, .limiter:
            runtimeDisposition = .live
        }

        saveConfig(restartRequired: runtimeDisposition == .restart)
        if runtimeDisposition == .restart {
            applyPendingRuntimeChanges()
        } else {
            applyLiveRuntimeConfigIfRunning()
        }
        statusText = selectedProcessingTab.resetStatusText
    }

    func resetCurrentRDSTabToDefaults() {
        publishConfigChange()
        let defaults = AppConfig()

        switch selectedRDSTab {
        case .program:
            config.enRDS = defaults.enRDS
            config.rdsPI = defaults.rdsPI
            config.rdsECC = defaults.rdsECC
            config.rdsPTY = defaults.rdsPTY
            config.rdsPSDynamic = defaults.rdsPSDynamic
            config.rdsPSCentered = defaults.rdsPSCentered
            config.rdsEnablePTYN = defaults.rdsEnablePTYN
            config.rdsPTYN = defaults.rdsPTYN
            config.rdsPTYNCentered = defaults.rdsPTYNCentered
        case .radiotext:
            config.rdsRTText = defaults.rdsRTText
            config.rdsRTManualBuffers = defaults.rdsRTManualBuffers
            config.rdsRTCycleAB = defaults.rdsRTCycleAB
            config.rdsRTA = defaults.rdsRTA
            config.rdsRTB = defaults.rdsRTB
            config.rdsRTCR = defaults.rdsRTCR
            config.rdsRTCentered = defaults.rdsRTCentered
            config.rdsRTMode = defaults.rdsRTMode
            config.rdsRTCycle = defaults.rdsRTCycle
            config.rdsRTCycleTime = defaults.rdsRTCycleTime
            config.rdsRTActiveBuffer = defaults.rdsRTActiveBuffer
            config.rdsRTABCycleCount = defaults.rdsRTABCycleCount
            config.rdsEnableRTPlus = defaults.rdsEnableRTPlus
            config.rdsRTPlusFormatA = defaults.rdsRTPlusFormatA
            config.rdsRTPlusFormatB = defaults.rdsRTPlusFormatB
            config.rdsNowPlayingEnabled = defaults.rdsNowPlayingEnabled
            config.rdsNowPlayingScript = defaults.rdsNowPlayingScript
            config.rdsNowPlayingPollSeconds = defaults.rdsNowPlayingPollSeconds
            config.rdsNowPlayingTimeoutSeconds = defaults.rdsNowPlayingTimeoutSeconds
        case .longPS:
            config.rdsLongPS32 = defaults.rdsLongPS32
            config.rdsEnableLPS = defaults.rdsEnableLPS
            config.rdsLPSCentered = defaults.rdsLPSCentered
            config.rdsLPSCR = defaults.rdsLPSCR
        case .flags:
            config.rdsTP = defaults.rdsTP
            config.rdsTA = defaults.rdsTA
            config.rdsMS = defaults.rdsMS
            config.rdsDI_STEREO = defaults.rdsDI_STEREO
            config.rdsDI_HEAD = defaults.rdsDI_HEAD
            config.rdsDI_COMP = defaults.rdsDI_COMP
            config.rdsDI_DYN = defaults.rdsDI_DYN
            config.rdsEnableAF = defaults.rdsEnableAF
            config.rdsAFList = defaults.rdsAFList
            config.rdsAFMethod = defaults.rdsAFMethod
            config.rdsLIC = defaults.rdsLIC
        case .carrier:
            config.rdsLevel = defaults.rdsLevel
            config.rdsGroupSequence = defaults.rdsGroupSequence
            config.rdsSchedulerAuto = defaults.rdsSchedulerAuto
            config.rdsSchedulerStandard = defaults.rdsSchedulerStandard
            config.rdsSchedulerStandardLPS = defaults.rdsSchedulerStandardLPS
            config.rdsEnableCT = defaults.rdsEnableCT
            config.rdsEnableID = defaults.rdsEnableID
            config.rdsTZOffset = defaults.rdsTZOffset
            config.rdsFreq = defaults.rdsFreq
            config.rdsGaussianEnabled = defaults.rdsGaussianEnabled
            config.rdsGaussianBWHZ = defaults.rdsGaussianBWHZ
            config.rdsGaussianTaps = defaults.rdsGaussianTaps
        }

        updateNowPlayingRunner()
        saveConfig(restartRequired: true)
        applyPendingRuntimeChanges()
        statusText = selectedRDSTab.resetStatusText
    }

    func loadConfigFromFile(_ path: String) {
        do {
            config = try AppConfig.load(fromINI: path)
            sourceMode = config.sourceMode
            monitorEnabled = config.monitorEnabled
            processingBypass = config.processingBypass
            inputGainDB = config.inputGainDB
            pendingRuntimeApply = false
            refreshDevices()
            updateNowPlayingRunner()
            statusText = "Config loaded: \(URL(fileURLWithPath: path).lastPathComponent)"
        } catch {
            statusText = "Config load failed: \(error)"
        }
    }

    func saveCurrentConfig() {
        saveConfig(restartRequired: false)
        statusText = "Config saved"
    }

    func saveConfigToFile(_ path: String) {
        do {
            try config.save(toINI: path)
            statusText = "Config saved: \(URL(fileURLWithPath: path).lastPathComponent)"
        } catch {
            statusText = "Config save failed: \(error)"
        }
    }

    func chooseNowPlayingScript() {
        let openPanel = NSOpenPanel()
        openPanel.message = "Choose a script to use for now playing metadata"
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowsMultipleSelection = false
        openPanel.prompt = "Choose Script"
        if !config.rdsNowPlayingScript.isEmpty {
            let currentPath = NowPlayingFormatter.normalizeScriptPath(config.rdsNowPlayingScript)
            openPanel.directoryURL = URL(fileURLWithPath: (currentPath as NSString).deletingLastPathComponent)
            openPanel.nameFieldStringValue = URL(fileURLWithPath: currentPath).lastPathComponent
        }

        openPanel.begin { [weak self] response in
            guard response == .OK, let url = openPanel.url else { return }
            Task { @MainActor in
                self?.setConfigValue(\.rdsNowPlayingScript, url.path, runtimeDisposition: .none)
            }
        }
    }

    func startOrStopTransport(forceStart: Bool? = nil) {
        let shouldStart = forceStart ?? !isRunning
        if shouldStart {
            startEngine()
        } else {
            stopEngine()
        }
    }

    func toggleBypass() {
        processingBypass.toggle()
        persistBasicConfig()
        if isRunning {
            restartEngineWithStatus("Bypass updated")
        }
    }

    func resetPeaks() {
        clearPeakHolds()
        statusText = "Monitoring peaks reset"
    }

    func setInputGainLive(_ value: Double) {
        inputGainDB = value
        config.inputGainDB = value
        saveConfig(restartRequired: false)
        applyLiveRuntimeConfigIfRunning()
    }

    private func applyLiveRuntimeConfigIfRunning() {
        guard isRunning, let runningEngine else { return }
        var runtimeConfig = config
        runtimeConfig.sourceMode = sourceMode
        runtimeConfig.monitorEnabled = monitorEnabled
        runtimeConfig.processingBypass = processingBypass
        runtimeConfig.inputGainDB = inputGainDB
        runningEngine.applyRuntimeConfig(runtimeConfig)
        pendingRuntimeApply = false
        statusText = "Live DSP parameters applied"
    }

    private func captureRuntimeSnapshot() -> RuntimeSnapshot {
        RuntimeSnapshot(
            config: config,
            sourceMode: sourceMode,
            monitorEnabled: monitorEnabled,
            processingBypass: processingBypass,
            inputGainDB: inputGainDB,
            selectedInputUID: selectedInputUID,
            selectedOutputUID: selectedOutputUID,
            selectedMonitorUID: selectedMonitorUID
        )
    }

    private func restoreRuntimeSnapshot(_ snapshot: RuntimeSnapshot) {
        config = snapshot.config
        sourceMode = snapshot.sourceMode
        monitorEnabled = snapshot.monitorEnabled
        processingBypass = snapshot.processingBypass
        inputGainDB = snapshot.inputGainDB
        selectedInputUID = snapshot.selectedInputUID
        selectedOutputUID = snapshot.selectedOutputUID
        selectedMonitorUID = snapshot.selectedMonitorUID
        updateNowPlayingRunner()
    }

    private func restartEngineWithStatus(_ status: String) {
        let wasRunning = isRunning
        let desiredSnapshot = captureRuntimeSnapshot()
        let fallbackSnapshot = activeRuntimeSnapshot
        stopEngine()
        if wasRunning {
            startEngine()
            if isRunning {
                statusText = "\(status) and applied"
                return
            }
            if let fallbackSnapshot {
                restoreRuntimeSnapshot(fallbackSnapshot)
                startEngine()
                if isRunning {
                    activeRuntimeSnapshot = fallbackSnapshot
                    restoreRuntimeSnapshot(desiredSnapshot)
                    pendingRuntimeApply = true
                    statusText = "\(status) failed; previous runtime restored. Pending changes kept."
                    return
                }
            }
            statusText = "\(status) failed; output remains stopped."
        }
    }

    private func startEngine() {
        guard !isTransitioning else { return }
        isTransitioning = true
        defer { isTransitioning = false }

        stopEngineIfNeeded()
        persistBasicConfig()

        var runConfig = config
        runConfig.sourceMode = sourceMode
        runConfig.monitorEnabled = monitorEnabled
        runConfig.processingBypass = processingBypass
        runConfig.inputGainDB = inputGainDB

        let inputID: AudioDeviceID? = {
            guard runConfig.sourceMode.lowercased() == "input" else { return nil }
            return inputDevices.first(where: { $0.uid == selectedInputUID })?.id
        }()

        let selectedOutUID = monitorEnabled ? selectedMonitorUID : selectedOutputUID
        let outputID: AudioDeviceID? = outputDevices.first(where: { $0.uid == selectedOutUID })?.id
        let outputMode: AudioOutputMode = monitorEnabled ? .monitorAudio : .mpxComposite

        let generator = MPXGenerator(
            config: runConfig,
            sampleRate: runConfig.sampleRate,
            nowPlayingState: nowPlayingState
        )
        let engine = AudioOutputEngine(
            generator: generator,
            config: runConfig,
            inputDeviceID: inputID,
            outputDeviceID: outputID,
            outputMode: outputMode
        )
        overflowHistory.removeAll(keepingCapacity: true)
        lastOverflowTotal = 0
        lastUnderflowTotal = 0
        clearPeakHolds()

        do {
            try engine.start()
            runningEngine = engine
            isRunning = true
            pendingRuntimeApply = false
            activeRuntimeSnapshot = captureRuntimeSnapshot()
            engineStartReference = Date().timeIntervalSinceReferenceDate
            let mode = monitorEnabled ? "monitor" : "output"
            var line =
                "Running source=\(runConfig.sourceMode) mode=\(mode) "
                + "render=\(Int(engine.renderSampleRate))Hz hw=\(Int(engine.hardwareSampleRate))Hz"
            if let note = engine.deviceRoutingNote {
                line += " (\(note))"
            }
            statusText = line
            refreshMonitoringSnapshot()
        } catch {
            statusText = "Start failed: \(error)"
            runningEngine = nil
            isRunning = false
        }
    }

    private func stopEngine() {
        guard !isTransitioning else { return }
        isTransitioning = true
        defer { isTransitioning = false }
        stopEngineIfNeeded()
        isRunning = false
        pendingRuntimeApply = false
        engineStartReference = nil
        overflowHistory.removeAll(keepingCapacity: true)
        lastOverflowTotal = 0
        lastUnderflowTotal = 0
        statusText = "Stopped"
        refreshMonitoringSnapshot()
    }

    private func stopEngineIfNeeded() {
        if let engine = runningEngine {
            engine.stop()
            runningEngine = nil
        }
    }

    private func refreshMonitoringSnapshot() {
        let now = Date().timeIntervalSinceReferenceDate
        let minRefreshInterval = 1.0 / Self.monitoringRefreshHz
        if let last = lastMonitorRefreshTime, (now - last) < minRefreshInterval {
            return
        }

        let dt = max(
            1.0 / (Self.monitoringRefreshHz * 2.0),
            min(0.25, now - (lastMonitorRefreshTime ?? (now - (1.0 / Self.monitoringRefreshHz))))
        )
        lastMonitorRefreshTime = now

        var inputPeak: Float = 0.0
        var outputPeak: Float = 0.0
        var deviationKHz: Float = 0.0
        var currentInputLeftPeak: Float = 0.0
        var currentInputRightPeak: Float = 0.0
        var currentOutputPeak: Float = 0.0
        var liveInputLeftPeak: Float = 0.0
        var liveInputRightPeak: Float = 0.0
        var liveOutputPeak: Float = 0.0
        var liveDeviationKHz: Float = 0.0
        var hasCapture = false
        var agcDetectorDB: Float = -120.0
        var agcGainDB: Float = 0.0
        var agcGateActive: Bool = false
        var compositeLimiterGainReductionDB: Float = 0.0
        var mpxSafetyLimiterGainReductionDB: Float = 0.0
        var pilotInjectionPercent: Float = 0.0
        var rdsInjectionPercent: Float = 0.0
        var audioCompositePeak: Float = 0.0
        var compositeBudgetMarginDB: Float = 0.0
        var outputStereoCorrelation: Float = 1.0
        var outputSideToMidRatio: Float = 0.0
        var loudnessAvailable: Bool = false
        var loudnessMomentaryLUFS: Float = -120.0
        var loudnessShortTermLUFS: Float = -120.0
        var loudnessIntegratedLUFS: Float = -120.0
        var health = MonitoringStreamHealth.stopped

        if let engine = runningEngine {
            let cap = engine.captureStats
            var runtime =
                "Running · Render \(Int(engine.renderSampleRate)) Hz · Hardware \(Int(engine.hardwareSampleRate)) Hz"
            if let inRate = engine.inputSampleRate {
                runtime += " · Input \(Int(inRate)) Hz"
            }
            runtime += " · Source \(engine.sourceDescription)"
            runtimeText = runtime
            health.isRunning = true
            health.inputName =
                sourceMode.lowercased() == "tone"
                ? "Tone Generator"
                : (inputDevices.first(where: { $0.uid == selectedInputUID })?.name.ifEmpty("None")
                    ?? "None")
            health.renderHz = Int(engine.renderSampleRate.rounded())
            health.inputHz = Int((engine.inputSampleRate ?? 0).rounded())
            health.blockFrames = engine.blockSize

            if let stats = engine.inputStats {
                inputRingText =
                    "Input Ring: \(stats.bufferedFrames) frames buffered · Overflows \(stats.overflows) · Underflows \(stats.underflows)"
                let target = max(1, engine.inputTargetFrames)
                inputBufferMax = Double(target * 2)
                inputBufferWarning = Double(target)
                inputBufferCritical = Double(target * 3 / 2)
                inputBufferValue = Double(stats.bufferedFrames)

                let deltaOverflows =
                    stats.overflows >= lastOverflowTotal ? (stats.overflows - lastOverflowTotal) : 0
                let deltaUnderflows =
                    stats.underflows >= lastUnderflowTotal
                    ? (stats.underflows - lastUnderflowTotal) : 0
                lastOverflowTotal = stats.overflows
                lastUnderflowTotal = stats.underflows
                if deltaOverflows > 0 || deltaUnderflows > 0 {
                    overflowHistory.append((now, deltaOverflows, deltaUnderflows))
                }
                overflowHistory.removeAll { now - $0.time > 10.0 }

                health.ringFrames = stats.bufferedFrames
                health.ringCapacity = target * 2
                let recentOverflows = overflowHistory.reduce(UInt64(0)) { $0 + $1.overflows }
                let recentUnderflows = overflowHistory.reduce(UInt64(0)) { $0 + $1.underflows }
                health.overflowsRecent = Int(min(UInt64(Int.max), recentOverflows))
                health.underflowsRecent = Int(min(UInt64(Int.max), recentUnderflows))
                health.overflowsTotal = Int(min(UInt64(Int.max), stats.overflows))
                health.underflowsTotal = Int(min(UInt64(Int.max), stats.underflows))
            } else {
                inputRingText =
                    "Input Ring: inactive (tone source) · Capture callbacks \(cap.callbacks)"
                inputBufferValue = 0
                inputBufferMax = 1
                inputBufferWarning = 0.7
                inputBufferCritical = 0.9
                overflowHistory.removeAll(keepingCapacity: true)
                lastOverflowTotal = 0
                lastUnderflowTotal = 0
            }

            let meters = engine.meters
            hasCapture = cap.callbacks > 0
            inputPeak = hasCapture ? meters.inputPeak : meters.outputPeak
            outputPeak = meters.outputPeak
            deviationKHz = meters.deviationKHzPeak
            currentInputLeftPeak = hasCapture ? meters.inputLeftPeak : meters.outputPeak
            currentInputRightPeak = hasCapture ? meters.inputRightPeak : meters.outputPeak
            currentOutputPeak = meters.outputPeak
            liveInputLeftPeak = hasCapture ? meters.liveInputLeftPeak : meters.liveOutputPeak
            liveInputRightPeak = hasCapture ? meters.liveInputRightPeak : meters.liveOutputPeak
            liveOutputPeak = meters.liveOutputPeak
            liveDeviationKHz = meters.liveDeviationKHzPeak
            agcDetectorDB = meters.agcDetectorDB
            agcGainDB = meters.agcGainDB
            agcGateActive = meters.agcGateActive
            compositeLimiterGainReductionDB = meters.compositeLimiterGainReductionDB
            mpxSafetyLimiterGainReductionDB = meters.mpxSafetyLimiterGainReductionDB
            pilotInjectionPercent = meters.pilotInjectionPercent
            rdsInjectionPercent = meters.rdsInjectionPercent
            audioCompositePeak = meters.audioCompositePeak
            compositeBudgetMarginDB = meters.compositeBudgetMarginDB
            outputStereoCorrelation = meters.outputStereoCorrelation
            outputSideToMidRatio = meters.outputSideToMidRatio
            loudnessAvailable = meters.loudnessAvailable
            loudnessMomentaryLUFS = meters.loudnessMomentaryLUFS
            loudnessShortTermLUFS = meters.loudnessShortTermLUFS
            loudnessIntegratedLUFS = meters.loudnessIntegratedLUFS

            if engineStartReference == nil {
                engineStartReference = now
            }

            updateScopes(engine: engine, inputPeak: inputPeak, outputPeak: outputPeak)
            if selectedSection == .monitoring || spectrumWindowVisible {
                updateMPXSpectrum(engine: engine, now: now)
            }
        } else {
            runtimeText = "Not running"
            inputRingText = "Input Ring: n/a"
            inputBufferValue = 0
            inputBufferMax = 1
            inputBufferWarning = 0.7
            inputBufferCritical = 0.9
            engineStartReference = nil
            lastMonitorRefreshTime = now
            inputScope = Array(repeating: 0.0, count: 128)
            outputScope = Array(repeating: 0.0, count: 128)
            smoothedInputScope = Array(repeating: 0.0, count: 128)
            smoothedOutputScope = Array(repeating: 0.0, count: 128)
            inputScopeGain = 1.0
            outputScopeGain = 1.0
            mpxSpectrumDB = Array(repeating: -100.0, count: 640)
            mpxSpectrumMaxHz = 92_000.0
            mpxSpectrumNyquistHz = 0.0
            lastSpectrumRefreshTime = nil
            spectrumUpdateInFlight = false
            vuInputL = 0.0
            vuInputR = 0.0
            vuOutput = 0.0
            vuModulation = 0.0
            clearPeakHolds()
            loudnessAvailable = false
            loudnessMomentaryLUFS = -120.0
            loudnessShortTermLUFS = -120.0
            loudnessIntegratedLUFS = -120.0
            limiterDetailText = String(
                format: "Drive %.1f dB • GR 0.0 dB • Max 0.0 dB • Safe 0.0 dB • Peak %@",
                config.finalDriveDB,
                Self.dbfsString(0.0)
            )
            compositeBudgetStateText = "Off"
            compositeCalibrationText = "Pilot 0.0% • RDS 0.0% • Audio -inf dBFS • Margin 0.0 dB"
            stereoImageText = "Corr +1.00 • Side 0.00x"
            widenerStateText = "Off"
            overflowHistory.removeAll(keepingCapacity: true)
            lastOverflowTotal = 0
            lastUnderflowTotal = 0
        }
        streamHealth = health

        self.loudnessAvailable = monitorEnabled && loudnessAvailable
        if self.loudnessAvailable {
            loudnessMomentaryText = Self.lufsString(loudnessMomentaryLUFS)
            loudnessShortTermText = Self.lufsString(loudnessShortTermLUFS)
            loudnessIntegratedText = Self.lufsString(loudnessIntegratedLUFS)
            loudnessStatusText = "Decoded monitor loudness in EBU-style M / S / I windows."
        } else {
            loudnessMomentaryText = "—"
            loudnessShortTermText = "—"
            loudnessIntegratedText = "—"
            loudnessStatusText =
                monitorEnabled
                ? "Waiting for decoded monitor audio to accumulate loudness windows."
                : "Enable Monitor Output to measure decoded-program loudness."
        }

        let modulationNorm = max(0.0, min(1.0, deviationKHz / 100.0))
        let inputLTarget = Self.levelMeterScale(currentInputLeftPeak)
        let inputRTarget = Self.levelMeterScale(currentInputRightPeak)
        let outputTarget = Self.levelMeterScale(currentOutputPeak)
        let modulationTarget = modulationNorm

        vuInputL = smoothPeakProgramMeter(
            current: vuInputL,
            target: inputLTarget,
            dt: dt,
            releaseMS: Self.audioPeakMeterReleaseMS
        )
        vuInputR = smoothPeakProgramMeter(
            current: vuInputR,
            target: inputRTarget,
            dt: dt,
            releaseMS: Self.audioPeakMeterReleaseMS
        )
        vuOutput = smoothPeakProgramMeter(
            current: vuOutput,
            target: outputTarget,
            dt: dt,
            releaseMS: Self.audioPeakMeterReleaseMS
        )
        vuModulation = smoothMeter(
            current: vuModulation,
            target: modulationTarget,
            dt: dt,
            attackMS: Self.meterAttackMS,
            releaseMS: Self.meterReleaseMS
        )

        inputLLevel = Double(max(0.0, min(1.0, vuInputL)))
        inputRLevel = Double(max(0.0, min(1.0, vuInputR)))
        outputLevel = Double(max(0.0, min(1.0, vuOutput)))
        modulationLevel = Double(max(0.0, min(1.0, vuModulation)))

        let inputLPeakHoldDB = updateAudioPeakHold(
            livePeakLinear: liveInputLeftPeak,
            state: &peakHoldInputL,
            dt: dt
        )
        let inputRPeakHoldDB = updateAudioPeakHold(
            livePeakLinear: liveInputRightPeak,
            state: &peakHoldInputR,
            dt: dt
        )
        let outputPeakHoldDB = updateAudioPeakHold(
            livePeakLinear: liveOutputPeak,
            state: &peakHoldOutput,
            dt: dt
        )
        inputLPeakHoldLevel = Double(Self.levelMeterScale(dbfs: inputLPeakHoldDB))
        inputRPeakHoldLevel = Double(Self.levelMeterScale(dbfs: inputRPeakHoldDB))
        outputPeakHoldLevel = Double(Self.levelMeterScale(dbfs: outputPeakHoldDB))
        modulationPeakHoldLevel = Double(
            updatePeakHold(
                livePeak: max(0.0, min(1.0, liveDeviationKHz / 100.0)),
                state: &peakHoldModulation,
                dt: dt
            ))
        let limiterGRPeakHold = updateLimiterGRPeakHold(
            liveValueDB: compositeLimiterGainReductionDB,
            dt: dt
        )

        inputLText = Self.peakMeterString(currentPeak: currentInputLeftPeak, peakHoldDB: inputLPeakHoldDB)
        inputRText = Self.peakMeterString(currentPeak: currentInputRightPeak, peakHoldDB: inputRPeakHoldDB)
        outputText = Self.peakMeterString(currentPeak: currentOutputPeak, peakHoldDB: outputPeakHoldDB)
        modulationText = String(format: "%.1f kHz", deviationKHz)

        let limiterState =
            config.compositeLimiterEnabled
            ? (compositeLimiterGainReductionDB >= 0.2 ? "Active" : "Idle") : "Off"
        limiterStateText = limiterState
        limiterDetailText = String(
            format: "Drive %.1f dB • GR %.1f dB • Max %.1f dB • Safe %.1f dB • Peak %@",
            config.finalDriveDB,
            compositeLimiterGainReductionDB,
            limiterGRPeakHold,
            mpxSafetyLimiterGainReductionDB,
            Self.dbfsString(outputPeak)
        )
        if !isRunning {
            compositeBudgetStateText = "Off"
        } else if compositeBudgetMarginDB >= 3.0 {
            compositeBudgetStateText = "Safe"
        } else if compositeBudgetMarginDB >= 1.0 {
            compositeBudgetStateText = "Tight"
        } else {
            compositeBudgetStateText = "Risk"
        }
        compositeCalibrationText = String(
            format: "Pilot %.1f%% • RDS %.1f%% • Audio %@ • Margin %.1f dB",
            pilotInjectionPercent,
            rdsInjectionPercent,
            Self.dbfsString(audioCompositePeak),
            compositeBudgetMarginDB
        )
        stereoImageText = String(
            format: "Corr %@%.2f • Side %.2fx",
            outputStereoCorrelation >= 0 ? "+" : "",
            outputStereoCorrelation,
            outputSideToMidRatio
        )
        if config.widebandAGCEnabled && !processingBypass {
            agcStateText = agcGateActive ? "Gate" : "On"
        } else {
            agcStateText = "Off"
        }
        agcDetailText = String(
            format: "Detector %.1f dB • Gain %.1f dB",
            agcDetectorDB,
            agcGainDB
        ) + (agcGateActive ? " • Gate" : "")
        multibandStateText = config.multibandEnabled ? "On" : "Off"
        orbassStateText = config.orbassEnabled ? "On" : "Off"
        if !config.stereoWidenEnabled || config.monoMode {
            widenerStateText = "Off"
        } else if outputStereoCorrelation < 0.0 || outputSideToMidRatio > 0.85 {
            widenerStateText = "Risk"
        } else if outputStereoCorrelation < 0.30 || outputSideToMidRatio > 0.55 {
            widenerStateText = "Wide"
        } else {
            widenerStateText = "Safe"
        }

        let elapsed = max(0.0, now - (engineStartReference ?? now))
        updateRDSFields(elapsed: elapsed)
    }

    private func updateScopes(engine: AudioOutputEngine, inputPeak: Float, outputPeak: Float) {
        let snapshot = engine.scopeSnapshot(windowMS: scopeTimebaseMS)
        if snapshot.input.isEmpty || snapshot.output.isEmpty {
            inputScope = Array(repeating: 0.0, count: 128)
            outputScope = Array(repeating: 0.0, count: 128)
            smoothedInputScope = inputScope
            smoothedOutputScope = outputScope
            inputScopeGain = 1.0
            outputScopeGain = 1.0
            return
        }

        inputScope = smoothedScopeSamples(
            snapshot.input,
            fallbackPeak: inputPeak,
            previous: &smoothedInputScope,
            gainState: &inputScopeGain,
            autoGain: scopeAutoGainEnabled
        )
        outputScope = smoothedScopeSamples(
            snapshot.output,
            fallbackPeak: outputPeak,
            previous: &smoothedOutputScope,
            gainState: &outputScopeGain,
            autoGain: scopeAutoGainEnabled
        )
    }

    private func updateMPXSpectrum(engine: AudioOutputEngine, now: TimeInterval) {
        let refreshInterval = 1.0 / 8.0
        if let last = lastSpectrumRefreshTime, (now - last) < refreshInterval {
            return
        }
        guard !spectrumUpdateInFlight else { return }
        lastSpectrumRefreshTime = now
        spectrumUpdateInFlight = true
        let raw = engine.outputSignalWindow(frameCount: 4096)
        let samples = raw.samples
        let sampleRate = raw.sampleRate

        let maxDisplayHz: Double = config.fftWindow96kHz ? 96_000.0 : 60_000.0
        let analyzer = spectrumAnalyzer
        spectrumQueue.async { [weak self] in
            let spectrum = analyzer.compute(
                samples: samples,
                sampleRate: sampleRate,
                displayBins: 640,
                maxDisplayHz: maxDisplayHz
            )
            DispatchQueue.main.async {
                guard let self else { return }
                self.mpxSpectrumDB = spectrum.dbBins
                self.mpxSpectrumMaxHz = spectrum.maxHz
                self.mpxSpectrumNyquistHz = spectrum.nyquistHz
                self.spectrumUpdateInFlight = false
            }
        }
    }

    private func smoothedScopeSamples(
        _ samples: [Float],
        fallbackPeak: Float,
        previous: inout [Float],
        gainState: inout Float,
        autoGain: Bool
    ) -> [Float] {
        guard !samples.isEmpty else { return [] }
        if previous.count != samples.count {
            previous = Array(repeating: 0.0, count: samples.count)
        }

        let targetScale: Float
        if autoGain {
            let measuredPeak = samples.reduce(Float(0.0)) { current, value in
                max(current, fabsf(value.isFinite ? value : 0.0))
            }
            let fallback = fallbackPeak.isFinite ? max(0.0, min(2.0, fallbackPeak)) : 0.0
            // Target ~85% vertical utilization with bounded auto-gain.
            let referencePeak = max(0.01, min(1.2, max(measuredPeak, fallback * 0.55)))
            targetScale = min(8.0, max(1.0, 0.85 / referencePeak))
        } else {
            targetScale = 1.0
        }
        gainState = (gainState * 0.82) + (targetScale * 0.18)

        var smoothed = previous
        for i in samples.indices {
            let raw = samples[i].isFinite ? samples[i] : 0.0
            var sample = max(-1.2, min(1.2, raw)) * gainState
            if autoGain, fabsf(sample) < 0.0015 {
                sample *= 0.7
            }
            sample = max(-1.0, min(1.0, sample))
            smoothed[i] = (smoothed[i] * 0.62) + (sample * 0.38)
        }
        if smoothed.count > 2 {
            var spatial = smoothed
            for i in 1..<(smoothed.count - 1) {
                spatial[i] =
                    (smoothed[i - 1] * 0.12) + (smoothed[i] * 0.76) + (smoothed[i + 1] * 0.12)
            }
            smoothed = spatial
        }
        previous = smoothed
        return smoothed
    }

    private func updateRDSFields(elapsed: Double) {
        rdsPS = Self.currentTimedDisplayText(config.rdsPSDynamic, elapsed: elapsed).ifEmpty("-")
        rdsPI = config.rdsPI
        rdsPTY = Self.ptyName(for: config.rdsPTY)
        rdsPTYN = Self.currentTimedDisplayText(config.rdsPTYN, elapsed: elapsed).ifEmpty("-")
        rdsAID = config.rdsEnableRTPlus ? "AID: 4BD7 (GROUP 11A)" : "AID: OFF"
        rdsLongPS = Self.currentTimedDisplayText(config.rdsLongPS32, elapsed: elapsed).ifEmpty("-")
        rdsRadiotext = currentRTText(elapsed: elapsed).ifEmpty("-")
    }

    private func currentRTText(elapsed: Double) -> String {
        let nowPlayingSnapshot = nowPlayingState.currentSnapshot()
        let text: String
        if config.rdsRTManualBuffers {
            if config.rdsRTCycle {
                let cycle = max(1.0, config.rdsRTCycleTime)
                let idx = Int(elapsed / cycle) % 2
                let raw = idx == 0 ? config.rdsRTA : config.rdsRTB
                text = NowPlayingFormatter.expandTemplate(raw, snapshot: nowPlayingSnapshot)
            } else {
                let raw = config.rdsRTActiveBuffer == 0 ? config.rdsRTA : config.rdsRTB
                text = NowPlayingFormatter.expandTemplate(raw, snapshot: nowPlayingSnapshot)
            }
        } else {
            let expanded = NowPlayingFormatter.expandTemplate(config.rdsRTText, snapshot: nowPlayingSnapshot)
            text = Self.currentTimedDisplayText(expanded, elapsed: elapsed)
        }
        let width = config.rdsRTMode.uppercased() == "2B" ? 32 : 64
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= width {
            return trimmed
        }
        return String(trimmed.prefix(width))
    }

    private static func currentTimedDisplayText(_ raw: String, elapsed: Double) -> String {
        let seq = parseTimedDisplaySequence(raw)
        guard !seq.isEmpty else { return "" }
        if seq.count == 1 {
            return seq[0].text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let total = seq.reduce(0.0) { $0 + max(0.1, $1.duration) }
        let t = elapsed.truncatingRemainder(dividingBy: total)
        var acc: Double = 0.0
        for item in seq {
            acc += max(0.1, item.duration)
            if t <= acc {
                return item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return seq.last?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func parseTimedDisplaySequence(_ raw: String) -> [(
        duration: Double, text: String
    )] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return [(10.0, "")]
        }

        let slashParts = trimmed.split(separator: "/").map(String.init)
        if slashParts.count > 1 {
            var out: [(Double, String)] = []
            let prefixRegex = try? NSRegularExpression(
                pattern: #"^([0-9]+(?:\.[0-9]+)?)s:"#, options: [])
            for part in slashParts {
                let p = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if p.isEmpty { continue }
                if let prefixRegex {
                    let ns = p as NSString
                    if let match = prefixRegex.firstMatch(
                        in: p, options: [], range: NSRange(location: 0, length: ns.length)),
                        match.range.location == 0
                    {
                        let dur = Double(ns.substring(with: match.range(at: 1))) ?? 2.5
                        let textStart = match.range.location + match.range.length
                        let text = textStart < ns.length ? ns.substring(from: textStart) : ""
                        out.append((dur, text))
                        continue
                    }
                }
                out.append((2.5, p))
            }
            return out.isEmpty ? [(10.0, trimmed)] : out
        }

        let tokenRegex = try? NSRegularExpression(pattern: #"([0-9]+(?:\.[0-9]+)?)s:"#, options: [])
        if let tokenRegex {
            let ns = trimmed as NSString
            let matches = tokenRegex.matches(
                in: trimmed, options: [], range: NSRange(location: 0, length: ns.length))
            if !matches.isEmpty, matches[0].range.location == 0 {
                var out: [(Double, String)] = []
                for (idx, match) in matches.enumerated() {
                    let durRange = match.range(at: 1)
                    let duration = Double(ns.substring(with: durRange)) ?? 2.5
                    let textStart = match.range.location + match.range.length
                    let textEnd =
                        (idx + 1 < matches.count) ? matches[idx + 1].range.location : ns.length
                    let textRange = NSRange(
                        location: textStart, length: max(0, textEnd - textStart))
                    let text = ns.substring(with: textRange).trimmingCharacters(
                        in: .whitespacesAndNewlines)
                    out.append((duration, text))
                }
                if !out.isEmpty {
                    return out
                }
            }
        }

        return [(10.0, trimmed)]
    }

    private static let ptyNames: [String] = [
        "None", "News", "Current Affairs", "Information", "Sport", "Education", "Drama", "Culture",
        "Science", "Varied", "Pop Music", "Rock Music", "Easy Music", "Light Classical",
        "Serious Classical",
        "Other Music", "Weather", "Finance", "Children's", "Social Affairs", "Religion", "Phone-In",
        "Travel", "Leisure", "Jazz", "Country", "National Music", "Oldies", "Folk Music",
        "Documentary",
        "Alarm Test", "Alarm",
    ]

    private static let orbassPresets: [OrbassPreset] = [
        .init(
            id: "chr", title: "CHR/EDM", enabled: true, amount: 0.34, freqHz: 78, harmonics: 0.28,
            drive: 0.92, density: 0.56, subharmonicsEnabled: true, subharmonicsAmount: 0.16),
        .init(
            id: "urban", title: "Urban", enabled: true, amount: 0.32, freqHz: 74, harmonics: 0.24,
            drive: 0.88, density: 0.54, subharmonicsEnabled: true, subharmonicsAmount: 0.14),
        .init(
            id: "rock", title: "Rock", enabled: true, amount: 0.24, freqHz: 90, harmonics: 0.16,
            drive: 0.76, density: 0.44, subharmonicsEnabled: false, subharmonicsAmount: 0.08),
        .init(
            id: "ac", title: "AC/Pop", enabled: true, amount: 0.18, freqHz: 100, harmonics: 0.10,
            drive: 0.68, density: 0.36, subharmonicsEnabled: false, subharmonicsAmount: 0.06),
        .init(
            id: "talk", title: "Talk", enabled: true, amount: 0.08, freqHz: 120, harmonics: 0.04,
            drive: 0.48, density: 0.22, subharmonicsEnabled: false, subharmonicsAmount: 0.0),
    ]

    private static let multibandPresets: [MultibandPreset] = [
        .init(
            id: "3_chr", title: "3B CHR/EDM", mode: 3, lowHz: 290, highHz: 2500, x1Hz: nil,
            x2Hz: nil, x3Hz: nil, x4Hz: nil, lowThresholdDB: -23, lowRatio: 2.3, lowAttackMS: 20,
            lowReleaseMS: 310, midThresholdDB: -21, midRatio: 2.0, midAttackMS: 14,
            midReleaseMS: 235, highThresholdDB: -19, highRatio: 1.6, highAttackMS: 8,
            highReleaseMS: 165, kneeDB: 2.4, linkStrength: 0.42, releaseProgramDependent: true),
        .init(
            id: "3_rock", title: "3B Rock", mode: 3, lowHz: 310, highHz: 2550, x1Hz: nil, x2Hz: nil,
            x3Hz: nil, x4Hz: nil, lowThresholdDB: -21, lowRatio: 2.1, lowAttackMS: 22,
            lowReleaseMS: 325, midThresholdDB: -19, midRatio: 1.9, midAttackMS: 14,
            midReleaseMS: 245, highThresholdDB: -18, highRatio: 1.55, highAttackMS: 9,
            highReleaseMS: 175, kneeDB: 2.5, linkStrength: 0.44, releaseProgramDependent: true),
        .init(
            id: "3_ac", title: "3B AC/Pop", mode: 3, lowHz: 320, highHz: 2650, x1Hz: nil, x2Hz: nil,
            x3Hz: nil, x4Hz: nil, lowThresholdDB: -19, lowRatio: 1.9, lowAttackMS: 24,
            lowReleaseMS: 340, midThresholdDB: -17, midRatio: 1.7, midAttackMS: 16,
            midReleaseMS: 260, highThresholdDB: -16, highRatio: 1.4, highAttackMS: 10,
            highReleaseMS: 190, kneeDB: 3.0, linkStrength: 0.48, releaseProgramDependent: true),
        .init(
            id: "3_country", title: "3B Country", mode: 3, lowHz: 300, highHz: 2450, x1Hz: nil,
            x2Hz: nil, x3Hz: nil, x4Hz: nil, lowThresholdDB: -21, lowRatio: 2.2, lowAttackMS: 22,
            lowReleaseMS: 320, midThresholdDB: -19, midRatio: 1.9, midAttackMS: 15,
            midReleaseMS: 250, highThresholdDB: -17, highRatio: 1.5, highAttackMS: 10,
            highReleaseMS: 185, kneeDB: 2.6, linkStrength: 0.42, releaseProgramDependent: true),
        .init(
            id: "3_talk", title: "3B Talk", mode: 3, lowHz: 360, highHz: 3200, x1Hz: nil, x2Hz: nil,
            x3Hz: nil, x4Hz: nil, lowThresholdDB: -15, lowRatio: 1.5, lowAttackMS: 36,
            lowReleaseMS: 440, midThresholdDB: -14, midRatio: 1.4, midAttackMS: 30,
            midReleaseMS: 360, highThresholdDB: -13, highRatio: 1.22, highAttackMS: 20,
            highReleaseMS: 290, kneeDB: 4.0, linkStrength: 0.62, releaseProgramDependent: true),
        .init(
            id: "3_urban", title: "3B Urban", mode: 3, lowHz: 250, highHz: 2200, x1Hz: nil,
            x2Hz: nil, x3Hz: nil, x4Hz: nil, lowThresholdDB: -24, lowRatio: 2.7, lowAttackMS: 16,
            lowReleaseMS: 280, midThresholdDB: -22, midRatio: 2.4, midAttackMS: 11,
            midReleaseMS: 210, highThresholdDB: -20, highRatio: 1.9, highAttackMS: 6,
            highReleaseMS: 145, kneeDB: 2.1, linkStrength: 0.38, releaseProgramDependent: true),
        .init(
            id: "3_dance", title: "3B Dance", mode: 3, lowHz: 240, highHz: 2100, x1Hz: nil,
            x2Hz: nil, x3Hz: nil, x4Hz: nil, lowThresholdDB: -26, lowRatio: 2.9, lowAttackMS: 14,
            lowReleaseMS: 260, midThresholdDB: -24, midRatio: 2.6, midAttackMS: 10,
            midReleaseMS: 200, highThresholdDB: -22, highRatio: 2.0, highAttackMS: 5,
            highReleaseMS: 135, kneeDB: 1.9, linkStrength: 0.34, releaseProgramDependent: true),
        .init(
            id: "3_news", title: "3B News", mode: 3, lowHz: 360, highHz: 3200, x1Hz: nil, x2Hz: nil,
            x3Hz: nil, x4Hz: nil, lowThresholdDB: -15, lowRatio: 1.4, lowAttackMS: 38,
            lowReleaseMS: 480, midThresholdDB: -14, midRatio: 1.35, midAttackMS: 30,
            midReleaseMS: 390, highThresholdDB: -13, highRatio: 1.25, highAttackMS: 22,
            highReleaseMS: 320, kneeDB: 4.0, linkStrength: 0.62, releaseProgramDependent: true),
        .init(
            id: "3_jazz", title: "3B Jazz", mode: 3, lowHz: 330, highHz: 2800, x1Hz: nil, x2Hz: nil,
            x3Hz: nil, x4Hz: nil, lowThresholdDB: -18, lowRatio: 1.7, lowAttackMS: 30,
            lowReleaseMS: 420, midThresholdDB: -17, midRatio: 1.55, midAttackMS: 24,
            midReleaseMS: 330, highThresholdDB: -16, highRatio: 1.35, highAttackMS: 16,
            highReleaseMS: 250, kneeDB: 3.2, linkStrength: 0.52, releaseProgramDependent: true),
        .init(
            id: "3_classic", title: "3B Classical", mode: 3, lowHz: 360, highHz: 3400, x1Hz: nil,
            x2Hz: nil, x3Hz: nil, x4Hz: nil, lowThresholdDB: -14, lowRatio: 1.35, lowAttackMS: 42,
            lowReleaseMS: 520, midThresholdDB: -13, midRatio: 1.3, midAttackMS: 36,
            midReleaseMS: 430, highThresholdDB: -12, highRatio: 1.2, highAttackMS: 26,
            highReleaseMS: 340, kneeDB: 4.6, linkStrength: 0.66, releaseProgramDependent: true),
        .init(
            id: "5_chr", title: "5B CHR/EDM", mode: 5, lowHz: nil, highHz: nil, x1Hz: 90, x2Hz: 320,
            x3Hz: 1600, x4Hz: 6200, lowThresholdDB: -23, lowRatio: 2.25, lowAttackMS: 20,
            lowReleaseMS: 320, midThresholdDB: -21, midRatio: 1.9, midAttackMS: 13,
            midReleaseMS: 240, highThresholdDB: -19, highRatio: 1.6, highAttackMS: 8,
            highReleaseMS: 180, kneeDB: 2.6, linkStrength: 0.48, releaseProgramDependent: true),
        .init(
            id: "5_rock", title: "5B Rock", mode: 5, lowHz: nil, highHz: nil, x1Hz: 90, x2Hz: 340,
            x3Hz: 1550, x4Hz: 6100, lowThresholdDB: -21, lowRatio: 2.1, lowAttackMS: 20,
            lowReleaseMS: 320, midThresholdDB: -19, midRatio: 1.85, midAttackMS: 13,
            midReleaseMS: 240, highThresholdDB: -18, highRatio: 1.55, highAttackMS: 8,
            highReleaseMS: 175, kneeDB: 2.5, linkStrength: 0.46, releaseProgramDependent: true),
        .init(
            id: "5_ac", title: "5B AC/Pop", mode: 5, lowHz: nil, highHz: nil, x1Hz: 90, x2Hz: 350,
            x3Hz: 1800, x4Hz: 6800, lowThresholdDB: -17.5, lowRatio: 1.75, lowAttackMS: 28,
            lowReleaseMS: 375, midThresholdDB: -16.0, midRatio: 1.55, midAttackMS: 19,
            midReleaseMS: 300, highThresholdDB: -14.5, highRatio: 1.28, highAttackMS: 13,
            highReleaseMS: 225, kneeDB: 3.6, linkStrength: 0.52, releaseProgramDependent: true),
        .init(
            id: "5_classic", title: "5B Classical/Jazz", mode: 5, lowHz: nil, highHz: nil, x1Hz: 90,
            x2Hz: 360, x3Hz: 1700, x4Hz: 6500, lowThresholdDB: -17, lowRatio: 1.5, lowAttackMS: 36,
            lowReleaseMS: 450, midThresholdDB: -16, midRatio: 1.4, midAttackMS: 30,
            midReleaseMS: 360, highThresholdDB: -15, highRatio: 1.25, highAttackMS: 20,
            highReleaseMS: 280, kneeDB: 4.5, linkStrength: 0.60, releaseProgramDependent: true),
        .init(
            id: "5_talk", title: "5B Talk", mode: 5, lowHz: nil, highHz: nil, x1Hz: 110, x2Hz: 420,
            x3Hz: 2200, x4Hz: 7600, lowThresholdDB: -12.5, lowRatio: 1.24, lowAttackMS: 48,
            lowReleaseMS: 560, midThresholdDB: -11.8, midRatio: 1.18, midAttackMS: 40,
            midReleaseMS: 450, highThresholdDB: -11.2, highRatio: 1.08, highAttackMS: 30,
            highReleaseMS: 360, kneeDB: 5.2, linkStrength: 0.46, releaseProgramDependent: true),
        .init(
            id: "5_urban", title: "5B Urban", mode: 5, lowHz: nil, highHz: nil, x1Hz: 85, x2Hz: 300,
            x3Hz: 1300, x4Hz: 5400, lowThresholdDB: -23, lowRatio: 2.3, lowAttackMS: 18,
            lowReleaseMS: 295, midThresholdDB: -21, midRatio: 2.0, midAttackMS: 12,
            midReleaseMS: 220, highThresholdDB: -19, highRatio: 1.7, highAttackMS: 7,
            highReleaseMS: 155, kneeDB: 2.2, linkStrength: 0.42, releaseProgramDependent: true),
        .init(
            id: "5_dance", title: "5B Dance", mode: 5, lowHz: nil, highHz: nil, x1Hz: 80, x2Hz: 290,
            x3Hz: 1200, x4Hz: 5000, lowThresholdDB: -24, lowRatio: 2.5, lowAttackMS: 16,
            lowReleaseMS: 285, midThresholdDB: -22, midRatio: 2.1, midAttackMS: 11,
            midReleaseMS: 215, highThresholdDB: -20, highRatio: 1.75, highAttackMS: 6,
            highReleaseMS: 150, kneeDB: 2.0, linkStrength: 0.40, releaseProgramDependent: true),
        .init(
            id: "5_news", title: "5B News", mode: 5, lowHz: nil, highHz: nil, x1Hz: 110, x2Hz: 450,
            x3Hz: 2100, x4Hz: 7600, lowThresholdDB: -15, lowRatio: 1.4, lowAttackMS: 40,
            lowReleaseMS: 500, midThresholdDB: -14, midRatio: 1.35, midAttackMS: 34,
            midReleaseMS: 400, highThresholdDB: -13, highRatio: 1.25, highAttackMS: 24,
            highReleaseMS: 320, kneeDB: 4.3, linkStrength: 0.64, releaseProgramDependent: true),
        .init(
            id: "5_jazz", title: "5B Jazz", mode: 5, lowHz: nil, highHz: nil, x1Hz: 95, x2Hz: 360,
            x3Hz: 1600, x4Hz: 6200, lowThresholdDB: -18, lowRatio: 1.65, lowAttackMS: 32,
            lowReleaseMS: 430, midThresholdDB: -17, midRatio: 1.5, midAttackMS: 26,
            midReleaseMS: 340, highThresholdDB: -16, highRatio: 1.35, highAttackMS: 17,
            highReleaseMS: 260, kneeDB: 3.4, linkStrength: 0.54, releaseProgramDependent: true),
        .init(
            id: "5_oldies", title: "5B Oldies", mode: 5, lowHz: nil, highHz: nil, x1Hz: 90,
            x2Hz: 340, x3Hz: 1450, x4Hz: 5600, lowThresholdDB: -20, lowRatio: 1.8, lowAttackMS: 26,
            lowReleaseMS: 360, midThresholdDB: -18, midRatio: 1.7, midAttackMS: 18,
            midReleaseMS: 280, highThresholdDB: -17, highRatio: 1.45, highAttackMS: 11,
            highReleaseMS: 210, kneeDB: 3.0, linkStrength: 0.48, releaseProgramDependent: true),
    ]

    private static let finalStagePresets: [FinalStagePreset] = [
        .init(
            id: "balanced",
            title: "Balanced Music",
            agcEnabled: true,
            agcTargetDB: -16.0,
            agcAttackMS: 80.0,
            agcReleaseMS: 1200.0,
            agcMaxGainDB: 12.0,
            agcMinGainDB: -12.0,
            finalDriveDB: 6.0,
            compositeLimiterEnabled: true
        ),
        .init(
            id: "chr",
            title: "CHR / Dance",
            agcEnabled: true,
            agcTargetDB: -15.0,
            agcAttackMS: 55.0,
            agcReleaseMS: 900.0,
            agcMaxGainDB: 10.0,
            agcMinGainDB: -9.0,
            finalDriveDB: 8.0,
            compositeLimiterEnabled: true
        ),
        .init(
            id: "punchy",
            title: "Punchy Music",
            agcEnabled: true,
            agcTargetDB: -15.0,
            agcAttackMS: 60.0,
            agcReleaseMS: 1000.0,
            agcMaxGainDB: 11.0,
            agcMinGainDB: -10.0,
            finalDriveDB: 7.5,
            compositeLimiterEnabled: true
        ),
        .init(
            id: "speech",
            title: "Speech / Talk",
            agcEnabled: true,
            agcTargetDB: -14.0,
            agcAttackMS: 45.0,
            agcReleaseMS: 750.0,
            agcMaxGainDB: 10.0,
            agcMinGainDB: -8.0,
            finalDriveDB: 4.5,
            compositeLimiterEnabled: true
        ),
    ]

    private static func ptyName(for pty: Int) -> String {
        if ptyNames.indices.contains(pty) {
            return ptyNames[pty]
        }
        return "None"
    }

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }

    private static func sanitizeHex(_ raw: String, width: Int) -> String {
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
            return String(repeating: "0", count: width)
        }
        if filtered.count >= width {
            return String(filtered.suffix(width))
        }
        return String(repeating: "0", count: width - filtered.count) + filtered
    }

    private func saveConfig(restartRequired: Bool) {
        enqueueConfigSave(snapshot: config)
        if restartRequired && isRunning {
            if !pendingRuntimeApply {
                statusText = "Restart required for engine, routing, or encoder-structure changes. Use Apply Restart in Monitoring."
            }
            pendingRuntimeApply = true
        }
    }

    private func updateNowPlayingRunner() {
        nowPlayingRunner.updateConfig(config)
    }

    private enum ConfigReloadOrigin {
        case manual
        case external
    }

    enum RuntimeChangeDisposition {
        case restart
        case live
        case none
    }

    private func applyLoadedConfig(_ loadedConfig: AppConfig, origin: ConfigReloadOrigin) {
        config = loadedConfig
        sourceMode = config.sourceMode
        monitorEnabled = config.monitorEnabled
        processingBypass = config.processingBypass
        inputGainDB = config.inputGainDB
        refreshDevices()
        updateNowPlayingRunner()

        if isRunning {
            pendingRuntimeApply = true
            statusText =
                origin == .external
                ? "Config changed on disk. Restart-required changes are pending; use Apply Restart in Monitoring."
                : "Config reloaded. Restart-required changes are pending; use Apply Restart in Monitoring."
        } else {
            pendingRuntimeApply = false
            statusText = origin == .external ? "Config reloaded from disk" : "Config reloaded"
        }
    }

    private func startConfigWatcher() {
        stopConfigWatcher()
        let directory = (configPath as NSString).deletingLastPathComponent
        let fd = open(directory, O_EVTONLY)
        guard fd >= 0 else { return }
        configWatchFD = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleExternalConfigReloadIfNeeded()
        }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.configWatchFD >= 0 {
                close(self.configWatchFD)
                self.configWatchFD = -1
            }
        }
        configWatchSource = source
        source.resume()
    }

    private func stopConfigWatcher() {
        configReloadWorkItem?.cancel()
        configReloadWorkItem = nil
        configWatchSource?.cancel()
        configWatchSource = nil
        if configWatchFD >= 0 {
            close(configWatchFD)
            configWatchFD = -1
        }
    }

    private func scheduleExternalConfigReloadIfNeeded() {
        let now = Date().timeIntervalSinceReferenceDate
        if now < ignoreConfigReloadUntil {
            return
        }
        configReloadWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let now = Date().timeIntervalSinceReferenceDate
            if now < self.ignoreConfigReloadUntil {
                return
            }
            do {
                try self.applyExternalConfigReloadIfChanged()
            } catch {
                self.statusText = "Config reload failed: \(error)"
            }
        }
        configReloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func applyExternalConfigReloadIfChanged() throws {
        let loaded = try AppConfig.load(fromINI: configPath)
        applyLoadedConfig(loaded, origin: .external)
    }

    private func publishConfigChange() {
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }

    private func enqueueConfigSave(snapshot: AppConfig) {
        pendingConfigSnapshot = snapshot
        guard !configSaveInFlight else { return }
        configSaveInFlight = true
        processPendingConfigSave()
    }

    private func processPendingConfigSave() {
        guard let snapshot = pendingConfigSnapshot else {
            configSaveInFlight = false
            return
        }
        pendingConfigSnapshot = nil
        let path = configPath

        DispatchQueue.global(qos: .utility).async { [weak self] in
            var saveError: Error?
            do {
                try snapshot.save(toINI: path)
            } catch {
                saveError = error
            }

            DispatchQueue.main.async {
                guard let self else { return }
                if let saveError {
                    self.statusText = "Config save failed: \(saveError)"
                } else {
                    self.ignoreConfigReloadUntil = Date().timeIntervalSinceReferenceDate + 0.75
                }
                self.processPendingConfigSave()
            }
        }
    }

    private func selectUID(preferred: String?, from devices: [AudioDevice]) -> String {
        if let preferred, !preferred.isEmpty, devices.contains(where: { $0.uid == preferred }) {
            return preferred
        }
        return devices.first?.uid ?? ""
    }

    private func clearPeakHolds() {
        peakHoldInputL = AudioPeakHoldState()
        peakHoldInputR = AudioPeakHoldState()
        peakHoldOutput = AudioPeakHoldState()
        peakHoldModulation = PeakHoldState()
        limiterGRPeakHoldDB = 0.0
        limiterGRPeakHoldRemaining = 0.0
        inputLPeakHoldLevel = 0.0
        inputRPeakHoldLevel = 0.0
        outputPeakHoldLevel = 0.0
        modulationPeakHoldLevel = 0.0
    }

    private func updatePeakHold(livePeak: Float, state: inout PeakHoldState, dt: Double) -> Float {
        let live = max(0.0, min(1.0, livePeak.isFinite ? livePeak : 0.0))
        if !stickyPeaksEnabled {
            state.value = live
            state.holdRemaining = 0.0
            return live
        }
        if live >= state.value {
            state.value = live
            state.holdRemaining = max(0.0, meterPeakHoldSeconds)
            return state.value
        }
        if state.holdRemaining > 0.0 {
            state.holdRemaining = max(0.0, state.holdRemaining - dt)
            return state.value
        }
        let fallRate = max(1.0, meterPeakFallDBPerSecond)
        let fallFactor = powf(10.0, Float(-(fallRate * dt) / 20.0))
        state.value = max(live, state.value * fallFactor)
        if state.value < 1e-6 {
            state.value = 0.0
        }
        return state.value
    }

    private func updateAudioPeakHold(
        livePeakLinear: Float,
        state: inout AudioPeakHoldState,
        dt: Double
    ) -> Float {
        let liveDB = Self.dbfsValue(livePeakLinear)
        if !stickyPeaksEnabled {
            state.db = liveDB
            state.holdRemaining = 0.0
            return liveDB
        }
        if liveDB >= state.db {
            state.db = liveDB
            state.holdRemaining = max(0.0, meterPeakHoldSeconds)
            return state.db
        }
        if state.holdRemaining > 0.0 {
            state.holdRemaining = max(0.0, state.holdRemaining - dt)
            return state.db
        }
        let fallRate = max(1.0, meterPeakFallDBPerSecond)
        state.db = max(liveDB, state.db - Float(fallRate * dt))
        return state.db
    }

    private func updateLimiterGRPeakHold(liveValueDB: Float, dt: Double) -> Float {
        let live = max(0.0, liveValueDB.isFinite ? liveValueDB : 0.0)
        if !stickyPeaksEnabled {
            limiterGRPeakHoldDB = live
            limiterGRPeakHoldRemaining = 0.0
            return live
        }
        if live >= limiterGRPeakHoldDB {
            limiterGRPeakHoldDB = live
            limiterGRPeakHoldRemaining = max(0.0, meterPeakHoldSeconds)
            return limiterGRPeakHoldDB
        }
        if limiterGRPeakHoldRemaining > 0.0 {
            limiterGRPeakHoldRemaining = max(0.0, limiterGRPeakHoldRemaining - dt)
            return limiterGRPeakHoldDB
        }
        let fallRate = max(1.0, meterPeakFallDBPerSecond)
        limiterGRPeakHoldDB = max(live, limiterGRPeakHoldDB - Float(fallRate * dt))
        if limiterGRPeakHoldDB < 0.01 {
            limiterGRPeakHoldDB = 0.0
        }
        return limiterGRPeakHoldDB
    }

    private func smoothMeter(
        current: Float, target: Float, dt: Double, attackMS: Float, releaseMS: Float
    ) -> Float {
        let clampedTarget = max(0.0, min(1.0, target.isFinite ? target : 0.0))
        let tauMS = clampedTarget >= current ? max(1.0, attackMS) : max(5.0, releaseMS)
        let alpha = 1.0 - exp(-dt / (Double(tauMS) * 0.001))
        return current + ((clampedTarget - current) * Float(alpha))
    }

    private func smoothPeakProgramMeter(
        current: Float,
        target: Float,
        dt: Double,
        releaseMS: Float
    ) -> Float {
        let clampedTarget = max(0.0, min(1.0, target.isFinite ? target : 0.0))
        if clampedTarget >= current {
            return smoothMeter(
                current: current,
                target: clampedTarget,
                dt: dt,
                attackMS: Self.audioPeakMeterAttackMS,
                releaseMS: releaseMS
            )
        }
        return smoothMeter(
            current: current,
            target: clampedTarget,
            dt: dt,
            attackMS: Self.audioPeakMeterAttackMS,
            releaseMS: releaseMS
        )
    }

    private static func dbfsValue(_ linear: Float) -> Float {
        guard linear.isFinite, linear > 1e-9 else { return -120.0 }
        return 20.0 * log10f(linear)
    }

    private static func levelMeterScale(dbfs db: Float) -> Float {
        let floorDB: Float = -36.0
        let norm = max(0.0, min(1.0, (db - floorDB) / -floorDB))
        return norm
    }

    private static func levelMeterScale(_ linear: Float) -> Float {
        levelMeterScale(dbfs: dbfsValue(linear))
    }

    private static func dbfsString(_ linear: Float) -> String {
        guard linear > 1e-9 else { return "-inf dBFS" }
        let db = 20.0 * log10(Double(linear))
        return String(format: "%.1f dBFS", db)
    }

    private static func meterMetaString(rms: Float, peak: Float, peakHoldDB: Float? = nil) -> String {
        let rmsString = dbfsString(rms)
        let displayPeakDB: Double
        if let peakHold = peakHoldDB {
            displayPeakDB = Double(peakHold)
        } else {
            displayPeakDB = peak > 1e-9 ? (20.0 * log10(Double(peak))) : -120.0
        }
        return "\(rmsString)   \(String(format: "%.1f", displayPeakDB)) pk"
    }

    private static func peakMeterString(currentPeak: Float, peakHoldDB: Float? = nil) -> String {
        let currentString = dbfsString(currentPeak)
        guard let peakHoldDB else { return currentString }
        return "\(currentString)   \(String(format: "%.1f", peakHoldDB)) pk"
    }

    private static func lufsString(_ value: Float) -> String {
        guard value.isFinite, value > -119.5 else { return "—" }
        return String(format: "%.1f LUFS", value)
    }
}

extension String {
    fileprivate func ifEmpty(_ fallback: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

private struct RootView: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $model.selectedSection) {
                    Section {
                        ForEach(AppSection.allCases) { section in
                            Label(section.rawValue, systemImage: section.icon)
                                .tag(section)
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollDisabled(true)

                Spacer()
            }
            .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(model.selectedSection.detailTitle)
                        .font(.title2.weight(.semibold))
                    Spacer()
                }
                .padding(.top, 16)
                .padding(.horizontal, 22)
                .padding(.bottom, 8)

                Text(model.selectedSection.detailSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 16)

                Group {
                    switch model.selectedSection {
                    case .monitoring:
                        MonitoringDashboardView(model: model)
                    case .processing:
                        ProcessingSectionView(model: model)
                    case .rds:
                        RDSSectionView(model: model)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
                .padding(.horizontal, 4)
            
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct MonitoringDashboardView: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card(title: "Status") {
                    VStack(alignment: .leading, spacing: 12) {
                        MonitoringHealthSummaryRow(health: model.streamHealth)

                        HStack(spacing: 12) {
                            Button {
                                model.startOrStopTransport()
                            } label: {
                                HStack {
                                    Image(systemName: model.isRunning ? "stop.fill" : "play.fill")
                                    Text(model.isRunning ? "Stop" : "Start")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isBusy)
                            .keyboardShortcut("t", modifiers: [.command])

                            Button {
                                model.toggleBypass()
                            } label: {
                                HStack {
                                    Image(systemName: model.processingBypass ? "bolt.slash.fill" : "bolt.fill")
                                    Text(model.processingBypass ? "Bypass On" : "Bypass Off")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.isBusy)
                            .keyboardShortcut("b", modifiers: [.command])
                        }
                    }
                }

                Card(title: "Interfaces") {
                    MonitoringInterfacesPanel(
                        inputName: inputName,
                        outputName: outputName,
                        monitorEnabled: model.monitorEnabled,
                        monitorName: monitorName
                    )
                }

                Card(title: "DSP") {
                    MonitoringDSPStatusSectionView(model: model)
                }

                Card(title: "RDS") {
                    MonitoringRDSSnapshotSectionView(model: model)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var inputName: String {
        guard !model.selectedInputUID.isEmpty else { return "—" }
        return model.inputDevices.first(where: { $0.uid == model.selectedInputUID })?.name ?? "—"
    }

    private var outputName: String {
        guard !model.selectedOutputUID.isEmpty else { return "—" }
        return model.outputDevices.first(where: { $0.uid == model.selectedOutputUID })?.name ?? "—"
    }

    private var monitorName: String {
        guard model.monitorEnabled, !model.selectedMonitorUID.isEmpty else { return "—" }
        return model.outputDevices.first(where: { $0.uid == model.selectedMonitorUID })?.name ?? "—"
    }
}

private struct MonitoringTransportHeader: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 12) {
                Spacer()

                if model.runtimeApplyPending {
                    Button(model.runtimeApplyButtonTitle) {
                        model.applyPendingRuntimeChanges()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button(model.processingBypass ? "Bypass On" : "Bypass") {
                    model.toggleBypass()
                }
                .buttonStyle(.bordered)
                .disabled(model.isBusy)

                Button(model.isRunning ? "Stop" : "Start") {
                    model.startOrStopTransport()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)
            }
            if model.runtimeApplyPending {
                Text(model.runtimeApplyHintText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct MonitoringHealthSummaryRow: View {
    let health: MonitoringStreamHealth

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FlowStatusRow(items: [
                ("Transport", health.isRunning ? "Running" : "Stopped", indicatorColor),
                ("Buffer", health.bufferSummary, indicatorColor),
                ("Source", health.inputName, .secondary.opacity(0.75)),
            ])

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 180), spacing: 12),
                    GridItem(.flexible(minimum: 180), spacing: 12),
                ],
                alignment: .leading,
                spacing: 12
            ) {
                DSPMetricGroupCard(
                    title: "Stream",
                    subtitle: "Current source and sample-rate path",
                    rows: [
                        ("Input", health.inputName),
                        ("Rates", rateText),
                    ]
                )
                DSPMetricGroupCard(
                    title: "Buffer",
                    subtitle: "Ring fill, estimated delay, and health state",
                    rows: [
                        ("Ring", ringText),
                        ("Delay", delayText),
                        ("Health", health.bufferSummary),
                    ]
                )
                DSPMetricGroupCard(
                    title: "Recent Dropouts",
                    subtitle: "Overflows and underflows over 10 seconds",
                    rows: [
                        ("Over", "\(health.overflowsRecent)"),
                        ("Under", "\(health.underflowsRecent)"),
                    ]
                )
                DSPMetricGroupCard(
                    title: "Totals",
                    subtitle: "Cumulative capture and render faults",
                    rows: [
                        ("Over", "\(health.overflowsTotal)"),
                        ("Under", "\(health.underflowsTotal)"),
                    ]
                )
            }
        }
    }

    private var ringText: String {
        if health.ringCapacity <= 0 {
            return "n/a"
        }
        let percent = Int(max(0.0, min(1.0, health.ringFill)) * 100.0)
        return "\(health.ringFrames) / \(health.ringCapacity) (\(percent)%)"
    }

    private var rateText: String {
        if health.inputHz > 0 {
            return "render \(health.renderHz) Hz • input \(health.inputHz) Hz"
        }
        return "render \(health.renderHz) Hz"
    }

    private var delayText: String {
        guard let delayMS = health.estimatedDelayMS else { return "n/a" }
        if delayMS >= 100.0 {
            return String(format: "%.0f ms", delayMS)
        }
        if delayMS >= 10.0 {
            return String(format: "%.1f ms", delayMS)
        }
        return String(format: "%.2f ms", delayMS)
    }

    private var indicatorColor: Color {
        guard health.isRunning else { return .secondary }
        switch health.bufferHealth {
        case .ok:
            return .green
        case .warn:
            return .orange
        case .bad:
            return .red
        }
    }
}

private struct MonitoringDetailValue: View {
    let key: String
    let value: String

    init(_ key: String, _ value: String) {
        self.key = key
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key)
            Text(value)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MonitoringRuntimeSectionView: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Runtime").font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Source") {
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.sourceMode },
                            set: {
                                model.sourceMode = $0
                                model.persistBasicConfig()
                            }
                        )
                    ) {
                        Text("input").tag("input")
                        Text("tone").tag("tone")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                LabeledContent("Input") {
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.selectedInputUID },
                            set: {
                                model.selectedInputUID = $0
                                model.persistBasicConfig()
                            }
                        )
                    ) {
                        ForEach(model.inputDevices, id: \.uid) { d in
                            Text(d.name).tag(d.uid)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityLabel("Input device")
                }
                LabeledContent("MPX Output") {
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.selectedOutputUID },
                            set: {
                                model.selectedOutputUID = $0
                                model.persistBasicConfig()
                            }
                        )
                    ) {
                        ForEach(model.outputDevices, id: \.uid) { d in
                            Text(d.name).tag(d.uid)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityLabel("Output device")
                }
                Toggle(
                    "Enable Monitor Output",
                    isOn: Binding(
                        get: { model.monitorEnabled },
                        set: {
                            model.monitorEnabled = $0
                            model.persistBasicConfig()
                        }
                    )
                )
                .toggleStyle(.checkbox)
                .accessibilityLabel("Enable monitor output")

                if model.monitorEnabled {
                    LabeledContent("Monitor Output Device (Decoded MPX Simulation)") {
                        Picker(
                            "",
                            selection: Binding(
                                get: { model.selectedMonitorUID },
                                set: {
                                    model.selectedMonitorUID = $0
                                    model.persistBasicConfig()
                                }
                            )
                        ) {
                            ForEach(model.outputDevices, id: \.uid) { d in
                                Text(d.name).tag(d.uid)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .accessibilityLabel("Monitor output device decoded MPX simulation")
                    }
                }
            }
        }
    }
}

private struct MonitoringRDSSnapshotSectionView: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        MonitoringRDSPanel(rows: model.rdsRows)
    }
}

private struct MonitoringInterfacesPanel: View {
    let inputName: String
    let outputName: String
    let monitorEnabled: Bool
    let monitorName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FlowStatusRow(items: [
                ("Source", "Ready", .green),
                ("Output", "Ready", .green),
                ("Monitor", monitorEnabled ? "Enabled" : "Off", monitorEnabled ? .green : .secondary.opacity(0.45)),
            ])

            DashboardMetricGrid {
                DSPMetricGroupCard(
                    title: "Input Source",
                    subtitle: "Active capture device",
                    rows: [
                        ("Device", inputName),
                        ("Role", "Program input"),
                    ]
                )
                DSPMetricGroupCard(
                    title: "Main Output",
                    subtitle: "Transmit and MPX routing",
                    rows: [
                        ("Device", outputName),
                        ("Role", "MPX output"),
                    ]
                )
                DSPMetricGroupCard(
                    title: "Monitor Path",
                    subtitle: "Decoded MPX monitor routing",
                    rows: [
                        ("State", monitorEnabled ? "Enabled" : "Off"),
                        ("Device", monitorEnabled ? monitorName : "—"),
                    ]
                )
            }
        }
    }
}

private struct MonitoringRDSPanel: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FlowStatusRow(items: summaryItems)

            DashboardMetricGrid {
                DSPMetricGroupCard(
                    title: "Program Service",
                    subtitle: "Station identity and classification",
                    rows: rowsFor(["PS", "PI", "PTY", "PTYN"])
                )
                DSPMetricGroupCard(
                    title: "Advanced Data",
                    subtitle: "RT+ application data and long text",
                    rows: rowsFor(["RT+ App ID", "Long PS"])
                )
                DSPMetricGroupCard(
                    title: "Radiotext",
                    subtitle: "Current transmitted text fields",
                    rows: rowsFor(["Radiotext", "Now Playing"])
                )
            }
        }
    }

    private var rowMap: [String: String] {
        Dictionary(uniqueKeysWithValues: rows)
    }

    private var summaryItems: [(title: String, value: String, color: Color)] {
        let ps = rowMap["PS"].flatMap { $0.isEmpty ? nil : $0 } ?? "—"
        let pty = rowMap["PTY"].flatMap { $0.isEmpty ? nil : $0 } ?? "—"
        let rt = rowMap["Radiotext"].flatMap { $0.isEmpty ? nil : $0 } ?? "—"
        let aid = rowMap["RT+ App ID"].flatMap { $0.isEmpty ? nil : $0 } ?? "OFF"
        return [
            ("PS", ps, .secondary.opacity(0.75)),
            ("PTY", pty, .secondary.opacity(0.75)),
            ("RT", rt == "-" || rt == "—" ? "Idle" : "Live", rt == "-" || rt == "—" ? .secondary.opacity(0.45) : .green),
            ("RT+", aid == "AID: OFF" || aid == "OFF" ? "Off" : "On", aid == "AID: OFF" || aid == "OFF" ? .secondary.opacity(0.45) : .green),
        ]
    }

    private func rowsFor(_ keys: [String]) -> [(String, String)] {
        keys.map { key in
            let rawValue = rowMap[key] ?? "—"
            if key == "RT+ App ID" {
                return (key, formattedAIDValue(rawValue))
            }
            return (key, rawValue)
        }
    }

    private func formattedAIDValue(_ rawValue: String) -> String {
        if rawValue.hasPrefix("AID: ") {
            return String(rawValue.dropFirst(5))
        }
        return rawValue
    }
}

private struct MonitoringLevelsSectionView: View {
    @ObservedObject var model: StereoFoolViewModel
    private let holdOptions: [Double] = [0.5, 1.0, 1.5, 2.0, 3.0]
    private let fallOptions: [Double] = [6.0, 12.0, 18.0, 24.0, 30.0]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Levels").font(.headline)

            HStack(spacing: 14) {
                Toggle(
                    "Sticky Peaks",
                    isOn: Binding(
                        get: { model.stickyPeaksEnabled },
                        set: { model.stickyPeaksEnabled = $0 }
                    )
                )
                .toggleStyle(.checkbox)
                Spacer(minLength: 12)
                Picker(
                    "Hold",
                    selection: Binding(
                        get: { model.meterPeakHoldSeconds },
                        set: { model.meterPeakHoldSeconds = $0 }
                    )
                ) {
                    ForEach(holdOptions, id: \.self) { seconds in
                        Text(String(format: "%.1f s", seconds)).tag(seconds)
                    }
                }
                .pickerStyle(.menu)
                .frame(minWidth: 100)
                Picker(
                    "Fall",
                    selection: Binding(
                        get: { model.meterPeakFallDBPerSecond },
                        set: { model.meterPeakFallDBPerSecond = $0 }
                    )
                ) {
                    ForEach(fallOptions, id: \.self) { value in
                        Text(String(format: "%.0f dB/s", value)).tag(value)
                    }
                }
                .pickerStyle(.menu)
                .frame(minWidth: 110)
                Button("Reset Peaks") {
                    model.resetPeaks()
                }
            }
            .controlSize(.small)
            .font(.callout)

            MeterRow(
                label: "Input L", valueText: model.inputLText, level: model.inputLLevel,
                peakLevel: model.inputLPeakHoldLevel, showsDBScale: true)
            MeterRow(
                label: "Input R", valueText: model.inputRText, level: model.inputRLevel,
                peakLevel: model.inputRPeakHoldLevel, showsDBScale: true)
            MeterRow(
                label: "MPX", valueText: model.outputText, level: model.outputLevel,
                peakLevel: model.outputPeakHoldLevel, showsDBScale: true)
            MeterRow(
                label: "Modulation", valueText: model.modulationText, level: model.modulationLevel,
                peakLevel: model.modulationPeakHoldLevel,
                scaleStyle: .modulation100kHz(limitKHz: model.config.mpxDeviationKHz))
        }
    }
}

private struct MonitoringDSPStatusSectionView: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DSP Status").font(.subheadline).foregroundStyle(.secondary)
            DSPOverviewPanel(model: model)
        }
    }

    static func compositeLimiterDotColor(for state: String) -> Color {
        if state.caseInsensitiveCompare("Idle") == .orderedSame {
            return .green
        }
        if state.caseInsensitiveCompare("Off") == .orderedSame
            || state.caseInsensitiveCompare("Disabled") == .orderedSame
        {
            return .secondary.opacity(0.45)
        }
        return .red
    }

    static func stereoImageDotColor(for state: String) -> Color {
        if state.caseInsensitiveCompare("Off") == .orderedSame {
            return .secondary.opacity(0.45)
        }
        if state.caseInsensitiveCompare("Safe") == .orderedSame {
            return .green
        }
        if state.caseInsensitiveCompare("Wide") == .orderedSame {
            return .orange
        }
        return .red
    }

    static func compositeBudgetDotColor(for state: String) -> Color {
        if state.caseInsensitiveCompare("Safe") == .orderedSame {
            return .green
        }
        if state.caseInsensitiveCompare("Tight") == .orderedSame {
            return .orange
        }
        if state.caseInsensitiveCompare("Off") == .orderedSame {
            return .secondary.opacity(0.45)
        }
        return .red
    }
}

private struct DSPOverviewPanel: View {
    @ObservedObject var model: StereoFoolViewModel

    private var limiterMetrics: [(String, String)] {
        metrics(from: model.limiterDetailText)
    }

    private var compositeMetrics: [(String, String)] {
        metrics(from: model.compositeCalibrationText)
    }

    private var stereoMetrics: [(String, String)] {
        metrics(from: model.stereoImageText)
    }

    private var agcMetrics: [(String, String)] {
        [
            ("Detector", metricValue(in: model.agcDetailText, for: "Detector") ?? "—"),
            ("Gain", metricValue(in: model.agcDetailText, for: "Gain") ?? "—"),
            ("State", model.agcStateText),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FlowStatusRow(items: [
                ("Limiter", model.limiterStateText, MonitoringDSPStatusSectionView.compositeLimiterDotColor(for: model.limiterStateText)),
                ("Budget", model.compositeBudgetStateText, MonitoringDSPStatusSectionView.compositeBudgetDotColor(for: model.compositeBudgetStateText)),
                ("AGC", model.agcStateText, agcDotColor),
                ("Multiband", model.multibandStateText, model.multibandStateText.caseInsensitiveCompare("On") == .orderedSame ? .green : .secondary.opacity(0.45)),
                ("Orbass", model.orbassStateText, model.orbassStateText.caseInsensitiveCompare("On") == .orderedSame ? .green : .secondary.opacity(0.45)),
                ("Image", model.widenerStateText, MonitoringDSPStatusSectionView.stereoImageDotColor(for: model.widenerStateText)),
            ])

            DashboardMetricGrid {
                DSPMetricGroupCard(
                    title: "Final Stage",
                    subtitle: "Drive, gain reduction, safety, and peak",
                    rows: limiterMetrics
                )
                DSPMetricGroupCard(
                    title: "Composite Budget",
                    subtitle: "Pilot, RDS, audio headroom, and margin",
                    rows: compositeMetrics
                )
                DSPMetricGroupCard(
                    title: "Stereo Image",
                    subtitle: "Correlation and side-energy balance",
                    rows: stereoMetrics
                )
                DSPMetricGroupCard(
                    title: "AGC Rider",
                    subtitle: "Detector level and active gain riding",
                    rows: agcMetrics
                )
            }
        }
    }

    private var agcDotColor: Color {
        if model.agcStateText.caseInsensitiveCompare("Off") == .orderedSame {
            return .secondary.opacity(0.45)
        }
        if model.agcStateText.caseInsensitiveCompare("Gate") == .orderedSame {
            return .orange
        }
        return .green
    }

    private func metrics(from text: String) -> [(String, String)] {
        text
            .split(separator: "•")
            .map { part in
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                let pieces = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                if pieces.count == 2 {
                    return (String(pieces[0]), String(pieces[1]))
                }
                return ("Value", trimmed)
            }
    }

    private func metricValue(in text: String, for key: String) -> String? {
        for part in text.split(separator: "•") {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("\(key) ") else { continue }
            return String(trimmed.dropFirst(key.count + 1))
        }
        return nil
    }
}

private struct DashboardMetricGrid<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 12)],
            alignment: .leading,
            spacing: 12
        ) {
            content
        }
    }
}

private struct FlowStatusRow: View {
    let items: [(title: String, value: String, color: Color)]

    var body: some View {
        ViewThatFits(in: .vertical) {
            HStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    DSPStatusPill(title: item.title, value: item.value, color: item.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    DSPStatusPill(title: item.title, value: item.value, color: item.color)
                }
            }
        }
    }
}

private struct DSPStatusPill: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DSPMetricGroupCard: View {
    let title: String
    let subtitle: String
    let rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                ForEach(rows.indices, id: \.self) { i in
                    GridRow {
                        Text(rows[i].0)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text(rows[i].1)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DSPStateIndicator: View {
    let title: String
    let dotColor: Color

    var body: some View {
        HStack(spacing: 6) {
            Text("\(title):")
                .foregroundStyle(.secondary)
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
        }
    }
}

private struct RuntimeCardView: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        Card(title: "Runtime") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("State") {
                    Text(model.isRunning ? "Running" : "Not running")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Source") {
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.sourceMode },
                            set: {
                                model.sourceMode = $0
                                model.persistBasicConfig()
                            }
                        )
                    ) {
                        Text("input").tag("input")
                        Text("tone").tag("tone")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                LabeledContent("Input") {
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.selectedInputUID },
                            set: {
                                model.selectedInputUID = $0
                                model.persistBasicConfig()
                            }
                        )
                    ) {
                        ForEach(model.inputDevices, id: \.uid) { d in
                            Text(d.name).tag(d.uid)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                LabeledContent("Output") {
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.selectedOutputUID },
                            set: {
                                model.selectedOutputUID = $0
                                model.persistBasicConfig()
                            }
                        )
                    ) {
                        ForEach(model.outputDevices, id: \.uid) { d in
                            Text(d.name).tag(d.uid)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                Toggle(
                    "Enable Monitor Output",
                    isOn: Binding(
                        get: { model.monitorEnabled },
                        set: {
                            model.monitorEnabled = $0
                            model.persistBasicConfig()
                        }
                    ))

                if model.monitorEnabled {
                    LabeledContent("Monitor Output Device (Decoded MPX Simulation)") {
                        Picker(
                            "",
                            selection: Binding(
                                get: { model.selectedMonitorUID },
                                set: {
                                    model.selectedMonitorUID = $0
                                    model.persistBasicConfig()
                                }
                            )
                        ) {
                            ForEach(model.outputDevices, id: \.uid) { d in
                                Text(d.name).tag(d.uid)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .accessibilityLabel("Monitor output device decoded MPX simulation")
                    }
                }

                Divider()
                Text(model.runtimeText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                ProgressView(value: model.inputBufferValue, total: max(1.0, model.inputBufferMax))
                    .tint(
                        model.inputBufferValue >= model.inputBufferCritical
                            ? .red
                            : (model.inputBufferValue >= model.inputBufferWarning
                                ? .yellow : .green))
                Text(model.inputRingText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .controlSize(.regular)
        }
    }
}

private struct RDSSnapshotCardView: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        Card(title: "RDS Snapshot") {
            KeyValueGrid(rows: model.rdsRows)
        }
    }
}

private struct RDSAdvancedCardView: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        Card(title: "Scheduler & Advanced") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Group Sequence", text: model.configBinding(\.rdsGroupSequence))
                Toggle("Scheduler Auto", isOn: model.configBinding(\.rdsSchedulerAuto))
                Toggle("Use Standard Schedule", isOn: model.configBinding(\.rdsSchedulerStandard))
                Toggle(
                    "Include LPS in Standard",
                    isOn: model.configBinding(\.rdsSchedulerStandardLPS))
                Toggle("Enable CT (4A)", isOn: model.configBinding(\.rdsEnableCT))
                Toggle("Enable ID (1A)", isOn: model.configBinding(\.rdsEnableID))

                Divider()

                LabeledContent("LIC") {
                    HexCodeField(text: model.hexByteBinding(\.rdsLIC), placeholder: "1D", width: 54)
                }
                DoubleSliderRow(
                    title: "Clock Offset", value: model.configBinding(\.rdsTZOffset),
                    range: -12...14, format: "%.1f h")
            }
        }
    }
}

private struct LevelsCardView: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        Card(title: "Levels") {
            VStack(alignment: .leading, spacing: 12) {
                MeterRow(
                    label: "Stereo Input L", valueText: model.inputLText, level: model.inputLLevel,
                    peakLevel: model.inputLPeakHoldLevel, showsDBScale: true)
                MeterRow(
                    label: "Stereo Input R", valueText: model.inputRText, level: model.inputRLevel,
                    peakLevel: model.inputRPeakHoldLevel, showsDBScale: true)
                MeterRow(
                    label: "MPX Output", valueText: model.outputText, level: model.outputLevel,
                    peakLevel: model.outputPeakHoldLevel, showsDBScale: true)
                MeterRow(
                    label: "Modulation", valueText: model.modulationText,
                    level: model.modulationLevel, peakLevel: model.modulationPeakHoldLevel,
                    scaleStyle: .modulation100kHz(limitKHz: model.config.mpxDeviationKHz))
            }
            .controlSize(.regular)
        }
    }
}

private struct LoudnessCardView: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        Card(title: "Loudness") {
            VStack(alignment: .leading, spacing: 12) {
                KeyValueGrid(rows: [
                    ("Momentary", model.loudnessMomentaryText),
                    ("Short-term", model.loudnessShortTermText),
                    ("Integrated", model.loudnessIntegratedText),
                ])

                Text(model.loudnessStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct MeterRow: View {
    enum ScaleStyle: Equatable {
        case dbfs
        case modulation100kHz(limitKHz: Double)
        case none
    }

    let label: String
    let valueText: String
    let level: Double
    let peakLevel: Double?
    let scaleStyle: ScaleStyle

    init(
        label: String, valueText: String, level: Double, peakLevel: Double? = nil,
        showsDBScale: Bool = false,
        scaleStyle: ScaleStyle? = nil
    ) {
        self.label = label
        self.valueText = valueText
        self.level = level
        self.peakLevel = peakLevel
        if let scaleStyle {
            self.scaleStyle = scaleStyle
        } else {
            self.scaleStyle = showsDBScale ? .dbfs : .none
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).foregroundStyle(.secondary)
                Spacer()
                Text(valueText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            MeterBar(level: level, peakLevel: peakLevel, scaleStyle: scaleStyle)
        }
        .font(.callout)
    }
}

private struct MeterBar: View {
    let level: Double
    let peakLevel: Double?
    let scaleStyle: MeterRow.ScaleStyle

    private struct ScaleTick: Identifiable {
        let position: Double
        let label: String

        var id: String { "\(label)-\(position)" }
    }

    private static func dbfsScalePosition(_ db: Double) -> Double {
        let floorDB = -36.0
        let clampedDB = min(0.0, max(floorDB, db))
        let norm = max(0.0, min(1.0, (clampedDB - floorDB) / -floorDB))
        return norm
    }

    private var scaleTicks: [ScaleTick] {
        switch scaleStyle {
        case .dbfs:
            return [
                ScaleTick(position: Self.dbfsScalePosition(-36.0), label: "-36"),
                ScaleTick(position: Self.dbfsScalePosition(-24.0), label: "-24"),
                ScaleTick(position: Self.dbfsScalePosition(-12.0), label: "-12"),
                ScaleTick(position: Self.dbfsScalePosition(-6.0), label: "-6"),
                ScaleTick(position: Self.dbfsScalePosition(-3.0), label: "-3"),
                ScaleTick(position: Self.dbfsScalePosition(0.0), label: "0 dBFS"),
            ]
        case .modulation100kHz:
            return [
                ScaleTick(position: 0.0, label: "0"),
                ScaleTick(position: 0.25, label: "25"),
                ScaleTick(position: 0.5, label: "50"),
                ScaleTick(position: 0.75, label: "75"),
                ScaleTick(position: 1.0, label: "100 kHz"),
            ]
        case .none:
            return []
        }
    }

    private var meterTint: Color {
        switch scaleStyle {
        case .modulation100kHz(let limitKHz):
            let limitNorm = max(0.01, min(1.0, limitKHz / 100.0))
            if level > limitNorm { return .red }
            if level >= (limitNorm * 0.95) { return .orange }
            if level >= (limitNorm * 0.80) { return .yellow }
            return .green
        case .dbfs, .none:
            if level >= 0.92 { return .red }
            if level >= 0.83 { return .orange }
            if level >= 0.66 { return .yellow }
            return .green
        }
    }

    private var targetLevel: Double? {
        switch scaleStyle {
        case .modulation100kHz(let limitKHz):
            return max(0.0, min(1.0, limitKHz / 100.0))
        case .dbfs, .none:
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                let width = max(0.0, min(1.0, level)) * geo.size.width
                let peakX = (peakLevel.map { max(0.0, min(1.0, $0)) } ?? 0.0) * geo.size.width
                let targetX = (targetLevel.map { max(0.0, min(1.0, $0)) } ?? 0.0) * geo.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.secondary.opacity(0.18))
                    ForEach(scaleTicks) { tick in
                        Rectangle()
                            .fill(Color.primary.opacity(0.15))
                            .frame(width: 1)
                            .offset(x: (tick.position * geo.size.width) - 0.5)
                    }
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(meterTint.opacity(0.75))
                        .frame(width: max(0.0, width))
                    if targetLevel != nil {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.95))
                            .frame(width: 2, height: 14)
                            .offset(
                                x: min(
                                    max(0.0, targetX - 1.0),
                                    max(0.0, geo.size.width - 2.0)
                                )
                            )
                    }
                    if peakLevel != nil {
                        Rectangle()
                            .fill(Color.primary.opacity(0.98))
                            .frame(width: 2, height: 14)
                            .offset(x: min(max(0.0, peakX - 1.0), max(0.0, geo.size.width - 2.0)))
                    }
                }
            }
            .frame(height: 14)
            if scaleStyle != .none {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        ForEach(scaleTicks) { tick in
                            Text(tick.label)
                                .font(.system(size: 9, weight: .regular, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .fixedSize()
                                .position(
                                    x: min(
                                        max(12.0, tick.position * geo.size.width),
                                        max(12.0, geo.size.width - 24.0)
                                    ),
                                    y: 7.0
                                )
                        }
                    }
                }
                .frame(height: 14)
            }
        }
        .transaction { txn in
            txn.animation = nil
        }
    }
}

private struct DSPStatusCardView: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        Card(title: "DSP Overview") {
            DSPOverviewPanel(model: model)
        }
    }
}

private struct ScopesCardView: View {
    @ObservedObject var model: StereoFoolViewModel
    private let scopeTimebasesMS: [Double] = [1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0]

    var body: some View {
        Card(title: "Scopes") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    LabeledContent("Window") {
                        Picker(
                            "",
                            selection: Binding(
                                get: { model.scopeTimebaseMS },
                                set: { model.scopeTimebaseMS = $0 }
                            )
                        ) {
                            ForEach(scopeTimebasesMS, id: \.self) { ms in
                                Text("\(Int(ms)) ms").tag(ms)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    Toggle(
                        "Auto Gain",
                        isOn: Binding(
                            get: { model.scopeAutoGainEnabled },
                            set: { model.scopeAutoGainEnabled = $0 }
                        )
                    )
                    .toggleStyle(.checkbox)
                    Spacer()
                }
                .font(.callout)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Stereo Input").font(.subheadline).foregroundStyle(.secondary)
                        ScopeView(samples: model.inputScope)
                            .accessibilityLabel("Input scope waveform")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MPX Output").font(.subheadline).foregroundStyle(.secondary)
                        ScopeView(samples: model.outputScope)
                            .accessibilityLabel("Output scope waveform")
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 6) {
                    Text("MPX FFT Analyzer").font(.subheadline).foregroundStyle(.secondary)
                    MPXSpectrumView(
                        dbBins: model.mpxSpectrumDB,
                        maxHz: model.mpxSpectrumMaxHz,
                        nyquistHz: model.mpxSpectrumNyquistHz
                    )
                }

                Text(
                    model.scopeAutoGainEnabled ? "Auto gain enabled." : "Fixed vertical scale: ±1.0"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ScopeView: View {
    let samples: [Float]

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(
                Path(roundedRect: rect, cornerRadius: 8), with: .color(.black.opacity(0.22)))

            var grid = Path()
            let midY = size.height * 0.5
            grid.move(to: CGPoint(x: 0, y: midY))
            grid.addLine(to: CGPoint(x: size.width, y: midY))
            for i in 1..<4 {
                let x = size.width * (CGFloat(i) / 4.0)
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            context.stroke(grid, with: .color(.white.opacity(0.12)), lineWidth: 1)

            guard samples.count > 1 else { return }
            let stepX = size.width / CGFloat(samples.count - 1)
            let amplitude = max(10.0, size.height * 0.46)

            var wave = Path()
            for (idx, sample) in samples.enumerated() {
                let clamped = max(-1.0, min(1.0, sample))
                let x = CGFloat(idx) * stepX
                let y = midY - (CGFloat(clamped) * amplitude)
                if idx == 0 {
                    wave.move(to: CGPoint(x: x, y: y))
                } else {
                    wave.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(wave, with: .color(.green.opacity(0.90)), lineWidth: 1.2)
        }
        .frame(minHeight: 130, idealHeight: 150)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct MPXSpectrumView: View {
    let dbBins: [Float]
    let maxHz: Double
    let nyquistHz: Double

    private let dbMin: Float = -100.0
    private let dbMax: Float = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 8), with: .color(.black.opacity(0.30)))
                let maxDisplayHz = max(1_000.0, maxHz)
                let nyquist = max(0.0, min(maxDisplayHz, nyquistHz))
                let leftAxisWidth: CGFloat = 42
                let rightAxisWidth: CGFloat = 42
                let topInset: CGFloat = 8
                let bottomInset: CGFloat = 20
                let plotRect = CGRect(
                    x: leftAxisWidth,
                    y: topInset,
                    width: max(10, size.width - leftAxisWidth - rightAxisWidth),
                    height: max(10, size.height - topInset - bottomInset)
                )

                // Grid and border inside the plot region.
                var grid = Path()
                for db in stride(from: -100, through: 0, by: 10) {
                    let y = yPosition(forDB: Float(db), in: plotRect)
                    grid.move(to: CGPoint(x: plotRect.minX, y: y))
                    grid.addLine(to: CGPoint(x: plotRect.maxX, y: y))
                }
                for tick in xTicks(maxHz: maxDisplayHz, dense: true) {
                    let x = xPosition(forHz: tick, in: plotRect, maxHz: maxDisplayHz)
                    grid.move(to: CGPoint(x: x, y: plotRect.minY))
                    grid.addLine(to: CGPoint(x: x, y: plotRect.maxY))
                }
                context.stroke(grid, with: .color(.white.opacity(0.18)), lineWidth: 0.9)
                context.stroke(
                    Path(plotRect),
                    with: .color(.white.opacity(0.40)),
                    lineWidth: 1.0
                )

                // Left and right Y-axis labels.
                for db in stride(from: -100, through: 0, by: 10) {
                    let y = yPosition(forDB: Float(db), in: plotRect)
                    let label = db == 0 ? "0 dB" : "\(db) dB"
                    let text = Text(label)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary)
                    context.draw(text, at: CGPoint(x: 18, y: y))
                    context.draw(text, at: CGPoint(x: size.width - 18, y: y))
                }

                // Bottom X-axis labels.
                for tick in xTicks(maxHz: maxDisplayHz, dense: false) {
                    let x = xPosition(forHz: tick, in: plotRect, maxHz: maxDisplayHz)
                    let kHz = Int((tick / 1000.0).rounded())
                    let label = Text("\(kHz) kHz")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary)
                    context.draw(label, at: CGPoint(x: x, y: plotRect.maxY + 12))
                }

                guard dbBins.count > 1 else { return }

                let stepX = plotRect.width / CGFloat(dbBins.count - 1)
                var line = Path()
                for (idx, value) in dbBins.enumerated() {
                    let x = plotRect.minX + (CGFloat(idx) * stepX)
                    let y = yPosition(forDB: max(dbMin, min(dbMax, value)), in: plotRect)
                    if idx == 0 {
                        line.move(to: CGPoint(x: x, y: y))
                    } else {
                        line.addLine(to: CGPoint(x: x, y: y))
                    }
                }

                var fill = line
                fill.addLine(to: CGPoint(x: plotRect.maxX, y: plotRect.maxY))
                fill.addLine(to: CGPoint(x: plotRect.minX, y: plotRect.maxY))
                fill.closeSubpath()
                let gradient = Gradient(colors: [
                    Color.red.opacity(0.65),
                    Color.yellow.opacity(0.60),
                    Color.green.opacity(0.55),
                    Color.cyan.opacity(0.50),
                    Color.blue.opacity(0.45),
                ])
                context.fill(
                    fill,
                    with: .linearGradient(
                        gradient, startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: 0, y: size.height)))
                context.stroke(line, with: .color(.white.opacity(0.7)), lineWidth: 1.0)

                if nyquist > 0.0, nyquist < maxDisplayHz {
                    let xNyquist = xPosition(forHz: nyquist, in: plotRect, maxHz: maxDisplayHz)
                    let unsupportedRect = CGRect(
                        x: xNyquist,
                        y: plotRect.minY,
                        width: max(0, plotRect.maxX - xNyquist),
                        height: plotRect.height
                    )
                    context.fill(
                        Path(unsupportedRect),
                        with: .color(.black.opacity(0.38))
                    )
                }
            }
            .frame(minHeight: 190, idealHeight: 220)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 14) {
                let maxDisplayHz = max(1_000.0, maxHz)
                if nyquistHz > 0.0, nyquistHz < maxDisplayHz {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.orange.opacity(0.9))
                            .frame(width: 6, height: 6)
                        Text("Nyquist \(Int((nyquistHz / 1000.0).rounded())) kHz")
                    }
                }
                Spacer()
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
        }
    }

    private func yPosition(forDB db: Float, height: CGFloat) -> CGFloat {
        let clamped = max(dbMin, min(dbMax, db))
        let norm = (clamped - dbMin) / (dbMax - dbMin)
        return (1.0 - CGFloat(norm)) * height
    }

    private func yPosition(forDB db: Float, in rect: CGRect) -> CGFloat {
        rect.minY + yPosition(forDB: db, height: rect.height)
    }

    private func xPosition(forHz hz: Double, in rect: CGRect, maxHz: Double) -> CGFloat {
        let ratio = CGFloat(max(0.0, min(1.0, hz / max(1_000.0, maxHz))))
        return rect.minX + (ratio * rect.width)
    }

    private func xTicks(maxHz: Double, dense: Bool) -> [Double] {
        let maxDisplayHz = max(1_000.0, maxHz)
        let step = dense ? 5_000.0 : 10_000.0
        var ticks: [Double] = [0.0]
        var value = step
        while value < maxDisplayHz {
            ticks.append(value)
            value += step
        }
        if ticks.last != maxDisplayHz {
            ticks.append(maxDisplayHz)
        }
        return ticks
    }
}

private struct KeyValueGrid: View {
    let rows: [(String, String)]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            ForEach(rows.indices, id: \.self) { i in
                GridRow {
                    Text(rows[i].0)
                        .foregroundStyle(.secondary)
                    Text(rows[i].1)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .font(.callout)
    }
}

private struct ProcessingSectionView: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $model.selectedProcessingTab) {
                ForEach(ProcessingTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch model.selectedProcessingTab {
                    case .core:
                        ProcessingCoreTab(model: model)
                    case .agc:
                        ProcessingAGCTab(model: model)
                    case .orbass:
                        ProcessingOrbassTab(model: model)
                    case .multiband:
                        ProcessingMultibandTab(model: model)
                    case .widener:
                        ProcessingWidenerTab(model: model)
                    case .limiter:
                        ProcessingLimiterTab(model: model)
                    }

                    HStack {
                        Spacer()
                        Button(model.selectedProcessingTab.resetButtonTitle) {
                            model.resetCurrentProcessingTabToDefaults()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(20)
                .frame(maxWidth: 1120, alignment: .topLeading)
            }
        }
    }
}

private struct ProcessingCoreTab: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        Card(title: "Core Processing") {
            Toggle("Bypass Processing", isOn: Binding(
                get: { model.processingBypass },
                set: { _ in model.toggleBypass() }
            ))
            Toggle("Mono Mode", isOn: model.configBinding(\.monoMode))
            Text("Mono Mode disables the stereo pilot, 38 kHz stereo subcarrier, and RDS so the transmitted composite is true mono.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Pre-emphasis", selection: model.configBinding(\.preemphasisUS)) {
                Text("Off").tag(0)
                Text("50 us").tag(50)
                Text("75 us").tag(75)
            }
            .pickerStyle(.segmented)
            DoubleSliderRow(title: "Input Gain", value: Binding(
                get: { model.inputGainDB },
                set: {
                    model.setInputGainLive($0)
                }
            ), range: -24...24, format: "%.1f dB")
            DoubleSliderRow(
                title: "MPX Output Level",
                value: model.configBinding(\.outputGainDB, runtimeDisposition: .live),
                range: -18...18,
                format: "%.1f dB"
            )
            Text("Use MPX Output Level for final transmit/output calibration. Do not use AGC target as the main loudness knob.")
                .font(.caption)
                .foregroundStyle(.secondary)
            DoubleSliderRow(title: "HPF", value: model.configBinding(\.hpfHz), range: 10...180, format: "%.0f Hz")
            DoubleSliderRow(title: "HF Trim", value: model.configBinding(\.hfTrimDB), range: -12...12, format: "%.1f dB")
            DoubleSliderRow(title: "HF Trim Freq", value: model.configBinding(\.hfTrimHz), range: 1_000...12_000, format: "%.0f Hz")
            DoubleSliderRow(title: "Program Lowpass", value: model.configBinding(\.programLowpassHz), range: 8_000...17_000, format: "%.0f Hz")
        }
    }
}

private struct ProcessingAGCTab: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        Card(title: "Wideband AGC") {
            Toggle("Enable Wideband AGC", isOn: model.configBinding(\.widebandAGCEnabled, runtimeDisposition: .live))
            DoubleSliderRow(title: "Platform Target", value: model.configBinding(\.widebandAGCTargetDB, runtimeDisposition: .live), range: -36 ... -6, format: "%.1f dB")
            DoubleSliderRow(title: "Attack", value: model.configBinding(\.widebandAGCAttackMS, runtimeDisposition: .live), range: 1...150, format: "%.1f ms")
            DoubleSliderRow(title: "Release", value: model.configBinding(\.widebandAGCReleaseMS, runtimeDisposition: .live), range: 40...1200, format: "%.1f ms")
            DoubleSliderRow(title: "Max Gain", value: model.configBinding(\.widebandAGCMaxGainDB, runtimeDisposition: .live), range: 0...24, format: "%.1f dB")
            DoubleSliderRow(title: "Min Gain", value: model.configBinding(\.widebandAGCMinGainDB, runtimeDisposition: .live), range: -24...0, format: "%.1f dB")
            Text("Wideband AGC should establish a stable average level platform. It is not the final loudness stage.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ProcessingOrbassTab: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        Card(title: "Orbass") {
            Picker("Preset", selection: Binding(
                get: { self.model.config.orbassPresetID },
                set: { newValue in
                    self.model.config.orbassPresetID = newValue
                    self.model.applyOrbassPreset(id: newValue)
                }
            )) {
                ForEach(model.orbassPresetChoices) { preset in
                    Text(preset.title).tag(preset.id)
                }
            }
            .pickerStyle(.menu)
            Toggle("Enable Orbass", isOn: model.configBinding(\.orbassEnabled, runtimeDisposition: .live))
            DoubleSliderRow(title: "Amount", value: model.configBinding(\.orbassAmount, runtimeDisposition: .live), range: 0...1.0, format: "%.2f")
            DoubleSliderRow(title: "Frequency", value: model.configBinding(\.orbassFreqHz, runtimeDisposition: .live), range: 40...180, format: "%.1f Hz")
            DoubleSliderRow(title: "Harmonics", value: model.configBinding(\.orbassHarmonics, runtimeDisposition: .live), range: 0...1.0, format: "%.2f")
            DoubleSliderRow(title: "Drive", value: model.configBinding(\.orbassDrive, runtimeDisposition: .live), range: 0.2...2.0, format: "%.2f")
            DoubleSliderRow(title: "Density", value: model.configBinding(\.orbassDensity, runtimeDisposition: .live), range: 0...1.0, format: "%.2f")
            Toggle("Enable Subharmonics", isOn: model.configBinding(\.orbassSubharmonicsEnabled, runtimeDisposition: .live))
            DoubleSliderRow(title: "Subharmonics", value: model.configBinding(\.orbassSubharmonicsAmount, runtimeDisposition: .live), range: 0...1.0, format: "%.2f")
                .disabled(!model.config.orbassSubharmonicsEnabled)
        }
    }
}

private struct ProcessingMultibandTab: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        Card(title: "Multiband Dynamics") {
            Picker("Preset", selection: Binding(
                get: { self.model.config.multibandPresetID },
                set: { newValue in
                    let intensity = MultibandPresetIntensity(rawValue: self.model.config.multibandIntensity) ?? .normal
                    self.model.config.multibandPresetID = newValue
                    self.model.applyMultibandPreset(id: newValue, intensity: intensity)
                }
            )) {
                ForEach(model.multibandPresetChoices) { preset in
                    Text(preset.title).tag(preset.id)
                }
            }
            Picker("Intensity", selection: Binding(
                get: { MultibandPresetIntensity(rawValue: self.model.config.multibandIntensity) ?? .normal },
                set: { newValue in
                    self.model.config.multibandIntensity = newValue.rawValue
                    self.model.applyMultibandPreset(id: self.model.config.multibandPresetID, intensity: newValue)
                }
            )) {
                ForEach(MultibandPresetIntensity.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Toggle("Enable Multiband", isOn: model.configBinding(\.multibandEnabled, runtimeDisposition: .live))
            Picker("Mode", selection: model.configBinding(\.multibandMode, runtimeDisposition: .live)) {
                Text("2-band").tag(2)
                Text("3-band").tag(3)
                Text("5-band").tag(5)
            }
            DoubleSliderRow(title: "Knee", value: model.configBinding(\.multibandKneeDB, runtimeDisposition: .live), range: 0...12, format: "%.1f dB")
            DoubleSliderRow(title: "Link", value: model.configBinding(\.multibandLinkStrength, runtimeDisposition: .live), range: 0...1, format: "%.2f")
            Toggle("Program-dependent Release", isOn: model.configBinding(\.multibandReleaseProgramDependent, runtimeDisposition: .live))
            DoubleSliderRow(title: "X1", value: model.configBinding(\.multibandX1Hz, runtimeDisposition: .live), range: 30...300, format: "%.0f Hz")
            DoubleSliderRow(title: "X2", value: model.configBinding(\.multibandX2Hz, runtimeDisposition: .live), range: 120...1200, format: "%.0f Hz")
            DoubleSliderRow(title: "X3", value: model.configBinding(\.multibandX3Hz, runtimeDisposition: .live), range: 600...4000, format: "%.0f Hz")
            DoubleSliderRow(title: "X4", value: model.configBinding(\.multibandX4Hz, runtimeDisposition: .live), range: 2500...12000, format: "%.0f Hz")
            DoubleSliderRow(title: "Low Threshold", value: model.configBinding(\.multibandLowThresholdDB, runtimeDisposition: .live), range: (-40)...(-6), format: "%.1f dB")
            DoubleSliderRow(title: "Mid Threshold", value: model.configBinding(\.multibandMidThresholdDB, runtimeDisposition: .live), range: (-40)...(-6), format: "%.1f dB")
            DoubleSliderRow(title: "High Threshold", value: model.configBinding(\.multibandHighThresholdDB, runtimeDisposition: .live), range: (-40)...(-6), format: "%.1f dB")
            DoubleSliderRow(title: "Low Ratio", value: model.configBinding(\.multibandLowRatio, runtimeDisposition: .live), range: 1...8, format: "%.2f")
            DoubleSliderRow(title: "Mid Ratio", value: model.configBinding(\.multibandMidRatio, runtimeDisposition: .live), range: 1...8, format: "%.2f")
            DoubleSliderRow(title: "High Ratio", value: model.configBinding(\.multibandHighRatio, runtimeDisposition: .live), range: 1...8, format: "%.2f")
            DoubleSliderRow(title: "Low Attack", value: model.configBinding(\.multibandLowAttackMS, runtimeDisposition: .live), range: 1...120, format: "%.1f")
            DoubleSliderRow(title: "Mid Attack", value: model.configBinding(\.multibandMidAttackMS, runtimeDisposition: .live), range: 1...120, format: "%.1f")
            DoubleSliderRow(title: "High Attack", value: model.configBinding(\.multibandHighAttackMS, runtimeDisposition: .live), range: 1...120, format: "%.1f")
            DoubleSliderRow(title: "Low Release", value: model.configBinding(\.multibandLowReleaseMS, runtimeDisposition: .live), range: 40...1200, format: "%.0f")
            DoubleSliderRow(title: "Mid Release", value: model.configBinding(\.multibandMidReleaseMS, runtimeDisposition: .live), range: 40...1200, format: "%.0f")
            DoubleSliderRow(title: "High Release", value: model.configBinding(\.multibandHighReleaseMS, runtimeDisposition: .live), range: 40...1200, format: "%.0f")
            DoubleSliderRow(title: "Makeup", value: model.configBinding(\.multibandMakeupDB, runtimeDisposition: .live), range: -12...18, format: "%.1f dB")
        }
    }
}

private struct ProcessingWidenerTab: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        Card(title: "Stereo Widener") {
            Toggle("Enable Stereo Widener", isOn: model.configBinding(\.stereoWidenEnabled, runtimeDisposition: .live))
            Toggle("Mono Bass", isOn: model.configBinding(\.monoBassEnabled, runtimeDisposition: .live))
            DoubleSliderRow(
                title: "Bass Mono Freq",
                value: model.configBinding(\.monoBassFreqHz, runtimeDisposition: .live),
                range: 70...220,
                format: "%.0f Hz"
            )
            .disabled(!model.config.monoBassEnabled)
            DoubleSliderRow(title: "Width", value: model.configBinding(\.stereoWidenWidth, runtimeDisposition: .live), range: 0...1, format: "%.2f")
            DoubleSliderRow(title: "Center", value: model.configBinding(\.stereoWidenCenter, runtimeDisposition: .live), range: 0...1, format: "%.2f")
            DoubleSliderRow(title: "Mix", value: model.configBinding(\.stereoWidenMix, runtimeDisposition: .live), range: 0...1, format: "%.2f")
        }
    }
}

private struct ProcessingLimiterTab: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        Card(title: "Composite Limiter") {
            Picker("Broadcast Preset", selection: Binding(
                get: { self.model.config.finalStagePresetID },
                set: { newValue in
                    self.model.config.finalStagePresetID = newValue
                    self.model.applyFinalStagePreset(id: newValue)
                }
            )) {
                ForEach(model.finalStagePresetChoices) { preset in
                    Text(preset.title).tag(preset.id)
                }
            }
            .pickerStyle(.menu)
            Toggle("Enable Composite Limiter", isOn: model.configBinding(\.compositeLimiterEnabled, runtimeDisposition: .live))
            DoubleSliderRow(
                title: "Final Drive",
                value: model.configBinding(\.finalDriveDB, runtimeDisposition: .live),
                range: 0...12,
                format: "%.1f dB"
            )
            Text("Broadcast Preset updates AGC platform and final-stage drive together. Final Drive feeds the final composite protection stage before MPX Output Level calibration.")
                .font(.caption)
                .foregroundStyle(.secondary)
            DoubleSliderRow(title: "Composite Deviation", value: model.configBinding(\.mpxDeviationKHz, runtimeDisposition: .live), range: 40...90, format: "%.1f kHz")
        }
    }
}

private struct LevelsOnlyView: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                LevelsCardView(model: model)
                LoudnessCardView(model: model)
            }
            .padding(20)
        }
    }
}

private struct SystemSettingsSectionContent: View {
    @ObservedObject var model: StereoFoolViewModel

    private let sampleRates: [Double] = [44_100, 48_000, 88_200, 96_000, 176_400, 192_000]
    private let blockSizes: [Int] = [1024, 2048, 4096, 8192]

    var body: some View {
        Group {
            Picker("Sample Rate", selection: model.configBinding(\.sampleRate)) {
                ForEach(sampleRates, id: \.self) { rate in
                    Text("\(Int(rate)) Hz").tag(rate)
                }
            }
            .pickerStyle(.menu)
            .disabled(model.isRunning)

            Picker("Block Size", selection: model.configBinding(\.blockSize)) {
                ForEach(blockSizes, id: \.self) { size in
                    Text("\(size)").tag(size)
                }
            }
            .pickerStyle(.menu)

            Toggle(
                "Auto Start at Launch",
                isOn: model.configBinding(\.rdsAutoStart, runtimeDisposition: .none))

            Toggle("Mono Mode", isOn: model.configBinding(\.monoMode))
            Text("Mono Mode transmits true mono composite only. Pilot and RDS are suppressed while it is enabled.")
                .font(.caption)
                .foregroundStyle(.secondary)

            DoubleSliderRow(
                title: "Pilot Level", value: model.configBinding(\.pilotLevel),
                range: 0...0.2, format: "%.3f")
            .disabled(model.config.monoMode)
            DoubleSliderRow(
                title: "Sum Level", value: model.configBinding(\.sumLevel),
                range: 0...1.5, format: "%.2f")
            DoubleSliderRow(
                title: "Diff Level", value: model.configBinding(\.diffLevel),
                range: 0...1.5, format: "%.2f")
            .disabled(model.config.monoMode)

            InlineRestartRequiredNote(
                text: "Sample rate, block size, mono mode, pre-emphasis, pilot/sum/diff levels, program lowpass, and other encoder-structure changes."
            )
        }
    }
}

private struct InterfacesSettingsSectionContent: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        Group {
            Picker(
                "Input Device",
                selection: Binding(
                    get: { model.selectedInputUID },
                    set: {
                        model.selectedInputUID = $0
                        model.persistBasicConfig()
                    }
                )
            ) {
                if model.inputDevices.isEmpty {
                    Text("No input devices").tag("")
                } else {
                    ForEach(model.inputDevices, id: \.uid) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
            }
            .pickerStyle(.menu)

                Picker(
                    "MPX Output Device",
                    selection: Binding(
                    get: { model.selectedOutputUID },
                    set: {
                        model.selectedOutputUID = $0
                        model.persistBasicConfig()
                    }
                )
            ) {
                if model.outputDevices.isEmpty {
                    Text("No output devices").tag("")
                } else {
                    ForEach(model.outputDevices, id: \.uid) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
            }
            .pickerStyle(.menu)

            Picker(
                "Monitor Output Device (Decoded MPX Simulation)",
                selection: Binding(
                    get: { model.selectedMonitorUID },
                    set: {
                        model.selectedMonitorUID = $0
                        model.persistBasicConfig()
                    }
                )
            ) {
                if model.outputDevices.isEmpty {
                    Text("No output devices").tag("")
                } else {
                    ForEach(model.outputDevices, id: \.uid) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
            }
            .pickerStyle(.menu)

            Toggle(
                "Enable Monitor Output",
                isOn: Binding(
                    get: { model.monitorEnabled },
                    set: {
                        model.monitorEnabled = $0
                        model.persistBasicConfig()
                    }
                ))

            Text("When Enable Monitor Output is on, this device is used for decoded MPX monitoring.")
                .font(.caption)
                .foregroundStyle(.secondary)

            InlineRestartRequiredNote(
                text: "Source mode, monitor output routing, and input/output/monitor device changes."
            )
        }
    }
}

private struct RDSSectionView: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $model.selectedRDSTab) {
                ForEach(RDSTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch model.selectedRDSTab {
                    case .program:
                        RDSProgramTab(model: model)
                    case .radiotext:
                        RDSRadiotextTab(model: model)
                    case .longPS:
                        RDSLongPSTab(model: model)
                    case .flags:
                        RDSFlagsTab(model: model)
                    case .carrier:
                        RDSCarrierTab(model: model)
                    }

                    HStack {
                        Spacer()
                        Button(model.selectedRDSTab.resetButtonTitle) {
                            model.resetCurrentRDSTabToDefaults()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(20)
                .frame(maxWidth: 1120, alignment: .topLeading)
            }
        }
    }
}

private struct RDSProgramTab: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        Card(title: "Program Service") {
            Toggle("Enable RDS", isOn: model.configBinding(\.enRDS))
            TextField("PS Dynamic", text: model.configBinding(\.rdsPSDynamic))
            Toggle("Center PS", isOn: model.configBinding(\.rdsPSCentered))
            LabeledContent("PI Code") {
                HexCodeField(text: model.piBinding(), placeholder: "0000", width: 72)
            }
            LabeledContent("ECC") {
                HexCodeField(text: model.hexByteBinding(\.rdsECC), placeholder: "E3", width: 54)
            }
            Picker("Program Type (PTY)", selection: model.ptyBinding()) {
                ForEach(model.ptyChoices, id: \.0) { pty in
                    Text("\(pty.0) · \(pty.1)").tag(pty.0)
                }
            }
            Toggle("Enable PTYN", isOn: model.configBinding(\.rdsEnablePTYN))
            TextField("PTYN", text: model.configBinding(\.rdsPTYN))
            Toggle("Center PTYN", isOn: model.configBinding(\.rdsPTYNCentered))
        }

        Card(title: "Snapshot") {
            KeyValueGrid(rows: model.rdsRows)
        }
    }
}

private struct HexCodeField: View {
    let text: Binding<String>
    let placeholder: String
    let width: CGFloat

    var body: some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundStyle(.tertiary))
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .multilineTextAlignment(.center)
            .frame(width: width)
            .textSelection(.enabled)
    }
}

private struct RDSRadiotextTab: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        Card(title: "Radiotext & RT+") {
            Toggle("Manual RT Buffers", isOn: model.configBinding(\.rdsRTManualBuffers))
            if model.value(for: \.rdsRTManualBuffers) {
                TextField("RT Buffer A", text: model.configBinding(\.rdsRTA))
                TextField("RT Buffer B", text: model.configBinding(\.rdsRTB))
                Picker("Active Buffer", selection: model.configBinding(\.rdsRTActiveBuffer)) {
                    Text("A").tag(0)
                    Text("B").tag(1)
                }
            } else {
                TextField("Radiotext", text: model.configBinding(\.rdsRTText))
            }
            Picker("RT Mode", selection: model.configBinding(\.rdsRTMode)) {
                Text("2A (64 chars)").tag("2A")
                Text("2B (32 chars)").tag("2B")
            }
            .pickerStyle(.segmented)
            Toggle("Cycle A/B", isOn: model.configBinding(\.rdsRTCycle))
            Toggle("Cycle Same Message A/B", isOn: model.configBinding(\.rdsRTCycleAB))
            DoubleSliderRow(
                title: "Cycle Time", value: model.configBinding(\.rdsRTCycleTime),
                range: 1...20, format: "%.1f s")
            IntStepperRow(
                title: "AB Cycle Count",
                value: model.configBinding(\.rdsRTABCycleCount), range: 1...99, step: 1,
                format: "%d")
            Toggle("Center RT", isOn: model.configBinding(\.rdsRTCentered))
            Toggle("Append CR", isOn: model.configBinding(\.rdsRTCR))
            Toggle("Enable RT+", isOn: model.configBinding(\.rdsEnableRTPlus))
            Divider()
            Toggle(
                "Enable Now Playing Script",
                isOn: model.configBinding(\.rdsNowPlayingEnabled, runtimeDisposition: .none))
            LabeledContent("Script Path") {
                HStack(spacing: 8) {
                    TextField(
                        "",
                        text: model.configBinding(\.rdsNowPlayingScript, runtimeDisposition: .none)
                    )
                    Button("Browse") {
                        model.chooseNowPlayingScript()
                    }
                    .buttonStyle(.bordered)
                }
            }
            DoubleSliderRow(
                title: "Poll Interval",
                value: model.configBinding(\.rdsNowPlayingPollSeconds, runtimeDisposition: .none),
                range: 1...60,
                format: "%.1f s"
            )
            DoubleSliderRow(
                title: "Script Timeout",
                value: model.configBinding(\.rdsNowPlayingTimeoutSeconds, runtimeDisposition: .none),
                range: 0.2...10,
                format: "%.1f s"
            )
            Text("Macros: {now_playing}, {artist}, {title}, {display}, {date}, {time}")
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.value(for: \.rdsNowPlayingEnabled) {
                Text("RT+ tags are derived from the structured script output when now playing is enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                TextField("RT+ Format A", text: model.configBinding(\.rdsRTPlusFormatA))
                TextField("RT+ Format B", text: model.configBinding(\.rdsRTPlusFormatB))
            }
            Text(model.rdsNowPlayingStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct RDSLongPSTab: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        Card(title: "Long PS") {
            Toggle("Enable Long PS (15A)", isOn: model.configBinding(\.rdsEnableLPS))
            TextField("Long PS Text", text: model.configBinding(\.rdsLongPS32))
            Toggle("Center Long PS", isOn: model.configBinding(\.rdsLPSCentered))
            Toggle("Append CR", isOn: model.configBinding(\.rdsLPSCR))
        }
    }
}

private struct RDSFlagsTab: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        Card(title: "Flags") {
            LazyVGrid(columns: [
                GridItem(.flexible(minimum: 100)),
                GridItem(.flexible(minimum: 100)),
                GridItem(.flexible(minimum: 100))
            ], alignment: .leading, spacing: 8) {
                Toggle("TP", isOn: model.configBinding(\.rdsTP))
                Toggle("TA", isOn: model.configBinding(\.rdsTA))
                Toggle("MS", isOn: model.configBinding(\.rdsMS))
                Toggle("DI Stereo", isOn: model.configBinding(\.rdsDI_STEREO))
                Toggle("DI Head", isOn: model.configBinding(\.rdsDI_HEAD))
                Toggle("DI Comp", isOn: model.configBinding(\.rdsDI_COMP))
                Toggle("DI Dyn PTY", isOn: model.configBinding(\.rdsDI_DYN))
            }
            .toggleStyle(.switch)

            Toggle("Enable AF", isOn: model.configBinding(\.rdsEnableAF))
            HStack(spacing: 12) {
                Picker("AF Method", selection: model.configBinding(\.rdsAFMethod)) {
                    Text("Method A").tag("A")
                    Text("Method B").tag("B")
                }
                .frame(width: 100)
                TextField("AF List", text: model.configBinding(\.rdsAFList))
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}

private struct RDSCarrierTab: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        Card(title: "RDS Carrier") {
            DoubleSliderRow(
                title: "RDS Level", value: model.configBinding(\.rdsLevel),
                range: 0...7.5, format: "%.2f kHz")
            DoubleSliderRow(
                title: "Subcarrier Frequency", value: model.configBinding(\.rdsFreq),
                range: 40_000...80_000, format: "%.0f Hz")
            Toggle("Gaussian Shaping", isOn: model.configBinding(\.rdsGaussianEnabled))
            DoubleSliderRow(
                title: "Gaussian BW", value: model.configBinding(\.rdsGaussianBWHZ),
                range: 600...6_000, format: "%.0f Hz")
            IntStepperRow(
                title: "Gaussian Taps", value: model.oddTapBinding(), range: 9...401,
                step: 2, format: "%d")
        }

        Card(title: "Scheduler & Advanced") {
            TextField("Group Sequence", text: model.configBinding(\.rdsGroupSequence))
            Toggle("Scheduler Auto", isOn: model.configBinding(\.rdsSchedulerAuto))
            Toggle("Use Standard Schedule", isOn: model.configBinding(\.rdsSchedulerStandard))
            Toggle(
                "Include LPS in Standard",
                isOn: model.configBinding(\.rdsSchedulerStandardLPS))
            Toggle("Enable CT (4A)", isOn: model.configBinding(\.rdsEnableCT))
            Toggle("Enable ID (1A)", isOn: model.configBinding(\.rdsEnableID))
            LabeledContent("LIC") {
                HexCodeField(text: model.hexByteBinding(\.rdsLIC), placeholder: "1D", width: 54)
            }
            DoubleSliderRow(
                title: "Clock Offset", value: model.configBinding(\.rdsTZOffset),
                range: -12...14, format: "%.1f h")
        }
    }
}

private struct RDSAdvancedTab: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        Card(title: "RDS Carrier") {
            DoubleSliderRow(
                title: "RDS Level", value: model.configBinding(\.rdsLevel),
                range: 0...7.5, format: "%.2f kHz")
            DoubleSliderRow(
                title: "Subcarrier Frequency", value: model.configBinding(\.rdsFreq),
                range: 40_000...80_000, format: "%.0f Hz")
            Toggle("Gaussian Shaping", isOn: model.configBinding(\.rdsGaussianEnabled))
            DoubleSliderRow(
                title: "Gaussian BW", value: model.configBinding(\.rdsGaussianBWHZ),
                range: 600...6_000, format: "%.0f Hz")
            IntStepperRow(
                title: "Gaussian Taps", value: model.oddTapBinding(), range: 9...401,
                step: 2, format: "%d")
        }
    }
}

private struct SettingsSectionView: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        Form {
            Section("Configuration") {
                LabeledContent("Path") {
                    Text(model.configFilePath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                HStack(spacing: 10) {
                    Button("Reveal Config") { model.revealConfigInFinder() }
                    Button("Reload Config") { model.reloadConfigFromDisk() }
                    Button("Refresh Devices") { model.refreshDevices() }
                }
            }

            Section("Interfaces") {
                InterfacesSettingsSectionContent(model: model)
            }

            Section("Audio Engine") {
                SystemSettingsSectionContent(model: model)
            }

            Section("Spectrum") {
                Toggle("96 kHz Window", isOn: model.configBinding(\.fftWindow96kHz))
                Text("When enabled, shows full 96 kHz spectrum. When disabled, shows the 60 kHz FM band.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 920, alignment: .topLeading)
        .padding(.horizontal, 10)
        .controlSize(.small)
    }
}

private struct SettingsWindowView: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        SettingsSectionView(model: model)
            .navigationTitle("Settings")
    }
}

private enum HelpTopic: String, CaseIterable, Identifiable {
    case inputLevels = "Input Levels"
    case rdsText = "RDS Text Format"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .inputLevels: return "waveform.path.ecg"
        case .rdsText: return "dot.radiowaves.left.and.right"
        }
    }
}

private struct HelpWindowView: View {
    @State private var selection: HelpTopic = .inputLevels

    var body: some View {
        HSplitView {
            List(HelpTopic.allCases, selection: $selection) { topic in
                Label(topic.rawValue, systemImage: topic.icon)
                    .symbolRenderingMode(.hierarchical)
                    .tag(topic)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 190, idealWidth: 220, maxWidth: 260)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(selection.rawValue)
                        .font(.title3.weight(.semibold))
                    switch selection {
                    case .inputLevels:
                        HelpInputLevelsView()
                    case .rdsText:
                        HelpRDSTextView()
                    }
                }
                .padding(20)
                .frame(maxWidth: 860, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private func CodeBlock(_ text: String) -> some View {
    Text(text)
        .font(.system(.callout, design: .monospaced))
        .textSelection(.enabled)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
}

private struct InlineRestartRequiredNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.clockwise.circle")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text("Restart Required")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
    }
}

private struct HelpInputLevelsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recommended operating targets for the current StereoFool FM chain. Feed it clean, consistent program audio and let the processor create the final density.")
                .foregroundStyle(.secondary)
                .font(.callout)

            GroupBox {
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Normal Peaks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("-6 to -3 dBFS")
                            .font(.body.weight(.semibold))
                    }
                    Divider().frame(height: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Occasional Peaks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("up to -2 dBFS")
                            .font(.body.weight(.semibold))
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Text("Notes")
                .font(.headline)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("• US nominal input alignment: around -20 dBFS")
                Text("• Europe (EBU R68) style alignment: around -18 dBFS")
                Text("• Do not hold the source at -2 dBFS all the time")
                Text("• If the input already looks slammed, back it down and let the chain work")
                Text("• Wideband AGC is a platform leveler, not the final loudness stage")
                Text("• Final Drive is the main loudness control before the composite limiter")
                Text("• MPX Output Level is for final exciter or interface calibration")
                Text("• Levels are peak safety meters; use Loudness only when Monitor Output is enabled")
                Text("If you hit 0 dBFS, reduce input gain or Final Drive and re-check pre-emphasis behavior.")
            }
            .foregroundStyle(.secondary)
            .font(.callout)

            Text("Restart-Required Settings")
                .font(.headline)
                .padding(.top, 4)

            InlineRestartRequiredNote(text: kRestartRequiredSettingsListText)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: 860, alignment: .leading)
    }
}

private struct HelpRDSTextView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timed text sequences for PS and Radiotext, plus now-playing macro support.")
                .foregroundStyle(.secondary)
                .font(.callout)

            Text("Syntax")
                .font(.headline)
                .padding(.top, 4)

            CodeBlock("10s:First/10s:Second")

            Text("Shows \"First\" for 10 seconds, then \"Second\" for 10 seconds, repeating.")
                .foregroundStyle(.secondary)
                .font(.callout)

            Text("Current supported syntax")
                .font(.headline)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                Text("• `Ns:Text` timed segments")
                Text("• `/` to separate repeating segments")
                Text("• Structured now-playing macros in Radiotext")
            }
            .foregroundStyle(.secondary)
            .font(.callout)

            Text("Examples")
                .font(.headline)
                .padding(.top, 8)

            CodeBlock("""
5s:StereoFool - 5s:FM Coder
20s:Station Name/10s:Now Playing
8s:Tune to 88.5/8s:My Frequency
""")

            Text("Now Playing macros")
                .font(.headline)
                .padding(.top, 8)

            CodeBlock("""
Now: {now_playing}
{artist} - {title}
{title}
{date} {time}
""")

            Text("Notes")
                .font(.headline)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                Text("• `{now_playing}` and `{display}` use the script display text")
                Text("• `{artist}` and `{title}` are preferred for RT+ tagging")
                Text("• When the now-playing script is enabled, RT+ tags are derived from structured script output automatically")
                Text("• In Mono Mode, pilot and RDS are suppressed, so transmitted RDS text is disabled until Mono Mode is turned off")
            }
            .foregroundStyle(.secondary)
            .font(.callout)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: 860, alignment: .leading)
    }
}

private struct HelpSectionView: View {
    var body: some View {
        Form {
            Section("Input Levels") {
                Text("Target levels for FM broadcast:")
                HStack {
                    VStack(alignment: .leading) {
                        Text("Peak").font(.caption).foregroundStyle(.secondary)
                        Text("-18 to -6 dBFS").font(.callout.monospaced())
                    }
                    Spacer()
                    VStack(alignment: .leading) {
                        Text("Average RMS").font(.caption).foregroundStyle(.secondary)
                        Text("-24 to -20 dBFS").font(.callout.monospaced())
                    }
                }
                Text("US: -20 dBFS nominal | Europe (EBU R68): -18 dBFS | Hot: -6 dBFS peak")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Keep average around -24 dB with peaks between -18 and -6 dBFS. If hitting 0 dBFS, reduce input gain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("RDS Text Format") {
                Text("PS Dynamic and RT support timed text segments:")
                Text("10s:First/10s:Second").font(.callout.monospaced()).foregroundStyle(.blue)
                Text("Shows 'First' for 10 seconds, then 'Second' for 10 seconds, then repeats.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("Examples:").font(.caption.bold())
                    Spacer()
                }
                Text("5s:StereoFool - 5s:FM Coder").font(.caption.monospaced())
                Text("20s:Station Name/10s:Now Playing").font(.caption.monospaced())
                Text("8s:Tune to 88.5/8s:My Frequency").font(.caption.monospaced())
            }
        }
        .formStyle(.grouped)
        .controlSize(.small)
    }
}

private struct AboutSectionView: View {
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("StereoFool")
                        .font(.title2.weight(.semibold))
                    Text("Version \(AppConfig.appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Copyright © 2026 Bkram Developments")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link("https://github.com/bkram/StereoFool", destination: URL(string: "https://github.com/bkram/StereoFool")!)
                        .font(.caption)
                }
                .padding(.vertical, 4)
            }

            Section {
                DisclaimerBox()
            }
        }
        .formStyle(.grouped)
        .controlSize(.small)
    }
}

private struct DisclaimerBox: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Disclaimer")
                    .font(.headline)
            }
            
            Text("StereoFool is a native macOS FM composite (MPX) generator with stereo encoding, optional RDS, and decoded monitor output.")
                .font(.caption)

            Text("This software is provided for experimental and educational purposes only and is not suitable for production broadcast use.")
                .font(.caption)
            
            Text("It may not conform to any applicable technical standards, regulatory requirements, or broadcast specifications related to:")
                .font(.caption)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("• RDS (Radio Data System)")
                Text("• FM composite (MPX) signal generation")
                Text("• RDS multiplex (RDS-MX) generation")
                Text("• Modulation accuracy, deviation limits, or spectral purity")
                Text("• Regional standards (e.g. EN 50067, IEC 62106, NRSC, ITU-R)")
            }
            .font(.caption)
            .padding(.leading, 8)
            
            Text("No warranty, guarantee, or representation is made that:")
                .font(.caption)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("• The generated composite or RDS signal meets required specifications")
                Text("• The output is suitable for on-air transmission")
                Text("• The software complies with any national or international broadcast regulations")
            }
            .font(.caption)
            .padding(.leading, 8)
            
            Text("Use of this software for transmission may require proper certification, measurement, and regulatory approval. The author assumes no liability for regulatory violations, equipment damage, interference, or any direct or indirect consequences arising from its use.")
                .font(.caption)
            
            Text("Use at your own risk.")
                .font(.caption.weight(.semibold))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct PendingApplyCard: View {
    @ObservedObject var model: StereoFoolViewModel

    

    var body: some View {
        // Empty view — never shown
        EmptyView()
        
        // Or completely remove the if and Card, leaving just:
        // EmptyView()
    }
    //     if model.runtimeApplyPending {
    //         Card(title: "Apply Pending") {
    //             HStack {
    //                 Text("Changes were saved. Restart runtime to apply them to audio output.")
    //                     .foregroundStyle(.secondary)
    //                 Spacer()
    //                 Button("Apply Now") {
    //                     model.applyPendingRuntimeChanges()
    //                 }
    //                 .buttonStyle(.borderedProminent)
    //             }
    //         }
    //         .hidden()
    //     }
}
    


private struct DoubleSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    var accessibilityLabel: String?

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 12) {
                Slider(value: $value, in: range)
                    .controlSize(.small)
                    .accessibilityLabel(accessibilityLabel ?? title)
                Text(String(format: format, value))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
            }
        }
    }
}

private struct IntStepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let format: String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 12) {
                Stepper("", value: $value, in: range, step: step)
                    .labelsHidden()
                Text(String(format: format, value))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 180, alignment: .trailing)
            }
        }
    }
}

struct ScopesOnlyView: View {
    @ObservedObject var model: StereoFoolViewModel
    private let scopeTimebasesMS: [Double] = [1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0]

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Scopes")
                    .font(.title2.weight(.semibold))
                Spacer()
                LabeledContent("Window") {
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.scopeTimebaseMS },
                            set: { model.scopeTimebaseMS = $0 }
                        )
                    ) {
                        ForEach(scopeTimebasesMS, id: \.self) { ms in
                            Text("\(Int(ms)) ms").tag(ms)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                Toggle(
                    "Auto Gain",
                    isOn: Binding(
                        get: { model.scopeAutoGainEnabled },
                        set: { model.scopeAutoGainEnabled = $0 }
                    )
                )
                .toggleStyle(.checkbox)
            }
            .padding(.horizontal)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Stereo Input").font(.subheadline).foregroundStyle(.secondary)
                    ScopeView(samples: model.inputScope)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("MPX Output").font(.subheadline).foregroundStyle(.secondary)
                    ScopeView(samples: model.outputScope)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(
                model.scopeAutoGainEnabled ? "Auto gain enabled." : "Fixed vertical scale: ±1.0"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.bottom)
        }
        .padding()
    }
}

struct SpectrumOnlyView: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("MPX Spectrum")
                    .font(.title2.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 6) {
                MPXSpectrumView(
                    dbBins: model.mpxSpectrumDB,
                    maxHz: model.mpxSpectrumMaxHz,
                    nyquistHz: model.mpxSpectrumNyquistHz
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
        .frame(minWidth: 600, minHeight: 300)
    }
}
