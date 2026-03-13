import Accelerate
import AppKit
import Combine
import CoreAudio
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// Sizes
private let kWindowWidth: CGFloat = 700
private let kWindowHeight: CGFloat = 330
private let kWindowMinWidth: CGFloat = 700
private let kWindowMinHeight: CGFloat = 330
private let kStereoFoolIconSymbol = "\u{1F3A7}"

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
}

enum RDSTab: String, CaseIterable, Identifiable {
    case program = "Program"
    case radiotext = "Radiotext"
    case longPS = "Long PS"
    case flags = "Flags"
    case carrier = "Carrier"

    var id: String { rawValue }
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
}

private struct PeakHoldState {
    var value: Float = 0.0
    var holdRemaining: Double = 0.0
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

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender == window {
            sender.orderOut(nil)
            return false
        } else if sender == scopesWindow {
            scopesWindow = nil
        } else if sender == spectrumWindow {
            spectrumWindow = nil
            model?.spectrumWindowVisible = false
        } else if sender == levelsWindow {
            levelsWindow = nil
        } else if sender == aboutWindow {
            aboutWindow = nil
        } else if sender == helpWindow {
            helpWindow = nil
        } else if sender == settingsWindow {
            settingsWindow = nil
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
            withTitle: "Apply Pending Changes", action: #selector(applyPendingChanges), keyEquivalent: "A")
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
        let app = NSApplication.shared
        if let existing = aboutWindow {
            if existing.isKeyWindow {
                existing.close()
            } else {
                existing.makeKeyAndOrderFront(nil)
                app.activate(ignoringOtherApps: true)
            }
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
        w.center()
        w.makeKeyAndOrderFront(nil)
        aboutWindow = w
        app.activate(ignoringOtherApps: true)
    }

    @objc private func showHelp() {
        let app = NSApplication.shared
        if let existing = helpWindow {
            if existing.isKeyWindow {
                existing.close()
            } else {
                existing.makeKeyAndOrderFront(nil)
                app.activate(ignoringOtherApps: true)
            }
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
        w.center()
        w.makeKeyAndOrderFront(nil)
        helpWindow = w
        app.activate(ignoringOtherApps: true)
    }

    @objc private func openDocs() {
        NSWorkspace.shared.open(URL(string: "https://github.com/bkram/StereoFool")!)
    }

    @objc private func showSettings() {
        let app = NSApplication.shared
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            app.activate(ignoringOtherApps: true)
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
        w.center()
        w.makeKeyAndOrderFront(nil)
        settingsWindow = w
        app.activate(ignoringOtherApps: true)
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
        let app = NSApplication.shared
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            app.activate(ignoringOtherApps: true)
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
        w.contentView = host
        w.makeKeyAndOrderFront(nil)
        window = w
        app.activate(ignoringOtherApps: true)
    }

    @objc private func showScopesWindow() {
        let app = NSApplication.shared
        if let existing = scopesWindow {
            if existing.isKeyWindow {
                existing.close()
            } else {
                existing.makeKeyAndOrderFront(nil)
                app.activate(ignoringOtherApps: true)
            }
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
        w.center()
        w.makeKeyAndOrderFront(nil)
        scopesWindow = w
        app.activate(ignoringOtherApps: true)
    }

    @objc private func showSpectrumWindow() {
        let app = NSApplication.shared
        if let existing = spectrumWindow {
            if existing.isKeyWindow {
                existing.close()
            } else {
                existing.makeKeyAndOrderFront(nil)
                app.activate(ignoringOtherApps: true)
            }
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
        w.center()
        w.makeKeyAndOrderFront(nil)
        spectrumWindow = w
        model?.spectrumWindowVisible = true
        app.activate(ignoringOtherApps: true)
    }

    @objc private func showLevelsWindow() {
        let app = NSApplication.shared
        if let existing = levelsWindow {
            if existing.isKeyWindow {
                existing.close()
            } else {
                existing.makeKeyAndOrderFront(nil)
                app.activate(ignoringOtherApps: true)
            }
            return
        }
        guard let vm = model else { return }
        let levelsView = LevelsOnlyView(model: vm)
        let hostingController = NSHostingController(rootView: levelsView)
        let w = NSWindow(contentViewController: hostingController)
        w.title = "Levels"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.setContentSize(NSSize(width: kWindowWidth, height: kWindowHeight))
        w.minSize = NSSize(width: kWindowMinWidth, height: kWindowMinHeight)
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        w.makeKeyAndOrderFront(nil)
        levelsWindow = w
        app.activate(ignoringOtherApps: true)
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

    @Published var limiterStateText: String = "Off"
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

    @Published var inputScope: [Float] = Array(repeating: 0.0, count: 128)
    @Published var outputScope: [Float] = Array(repeating: 0.0, count: 128)
    @Published var scopeTimebaseMS: Double = 10.0
    @Published var scopeAutoGainEnabled: Bool = true
    @Published var mpxSpectrumDB: [Float] = Array(repeating: -100.0, count: 640)
    @Published var mpxSpectrumMaxHz: Double = 92_000.0
    @Published var mpxSpectrumNyquistHz: Double = 0.0
    @Published var spectrumWindowVisible: Bool = false

    private let configPath: String
    var config: AppConfig
    private var runningEngine: AudioOutputEngine?
    private var monitorTimer: Timer?
    private var lastMonitorRefreshTime: TimeInterval?
    private var engineStartReference: TimeInterval?

    private var vuInputL: Float = 0.0
    private var vuInputR: Float = 0.0
    private var vuOutput: Float = 0.0
    private var vuModulation: Float = 0.0
    private var peakHoldInputL = PeakHoldState()
    private var peakHoldInputR = PeakHoldState()
    private var peakHoldOutput = PeakHoldState()
    private var peakHoldModulation = PeakHoldState()

    private var smoothedInputScope: [Float] = Array(repeating: 0.0, count: 128)
    private var smoothedOutputScope: [Float] = Array(repeating: 0.0, count: 128)
    private var inputScopeGain: Float = 1.0
    private var outputScopeGain: Float = 1.0
    private var overflowHistory: [(time: TimeInterval, overflows: UInt64, underflows: UInt64)] = []
    private var lastOverflowTotal: UInt64 = 0
    private var lastUnderflowTotal: UInt64 = 0
    private var pendingConfigSnapshot: AppConfig?
    private var configSaveInFlight: Bool = false
    private var lastSpectrumRefreshTime: TimeInterval?
    private var spectrumUpdateInFlight: Bool = false
    private let spectrumQueue = DispatchQueue(label: "StereoFool.MPXSpectrum", qos: .userInitiated)

    init(configPath: String) {
        self.configPath = configPath
        do {
            self.config = try AppConfig.load(fromINI: configPath)
        } catch {
            self.config = AppConfig()
            try? self.config.save(toINI: configPath)
        }

        self.sourceMode = config.sourceMode
        self.monitorEnabled = config.monitorEnabled
        self.processingBypass = config.processingBypass
        self.inputGainDB = config.inputGainDB

        refreshDevices()
        refreshMonitoringSnapshot()
    }

    var autoStartEnabled: Bool { config.rdsAutoStart }

    var isBusy: Bool { isTransitioning }

    var configFilePath: String { configPath }

    var runtimeApplyPending: Bool { isRunning && pendingRuntimeApply }

    var ptyChoices: [(Int, String)] {
        Self.ptyNames.enumerated().map { ($0.offset, $0.element) }
    }

    var orbassPresetChoices: [PresetChoice] {
        Self.orbassPresets.map { PresetChoice(id: $0.id, title: $0.title) }
    }

    var multibandPresetChoices: [PresetChoice] {
        Self.multibandPresets.map { PresetChoice(id: $0.id, title: $0.title) }
    }

    var rdsRows: [(String, String)] {
        [
            ("PS", rdsPS),
            ("PI", rdsPI),
            ("PTY", rdsPTY),
            ("PTYN", rdsPTYN),
            ("AID", rdsAID),
            ("Long PS", rdsLongPS),
            ("Radiotext", rdsRadiotext),
        ]
    }

    func startMonitoringTimer() {
        monitorTimer?.invalidate()
        let timer = Timer(timeInterval: (1.0 / 60.0), repeats: true) { [weak self] _ in
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
        restartRequired: Bool = true
    ) {
        objectWillChange.send()
        config[keyPath: keyPath] = value
        saveConfig(restartRequired: restartRequired)
    }

    func configBinding<T>(
        _ keyPath: WritableKeyPath<AppConfig, T>,
        restartRequired: Bool = true
    ) -> Binding<T> {
        Binding(
            get: { self.config[keyPath: keyPath] },
            set: { self.setConfigValue(keyPath, $0, restartRequired: restartRequired) }
        )
    }

    func ptyBinding() -> Binding<Int> {
        Binding(
            get: { self.config.rdsPTY },
            set: { self.setConfigValue(\.rdsPTY, max(0, min(31, $0)), restartRequired: true) }
        )
    }

    func piBinding() -> Binding<String> {
        Binding(
            get: { self.config.rdsPI },
            set: {
                self.setConfigValue(\.rdsPI, Self.sanitizeHex($0, width: 4), restartRequired: true)
            }
        )
    }

    func hexByteBinding(_ keyPath: WritableKeyPath<AppConfig, String>) -> Binding<String> {
        Binding(
            get: { self.config[keyPath: keyPath] },
            set: {
                self.setConfigValue(keyPath, Self.sanitizeHex($0, width: 2), restartRequired: true)
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
                self.setConfigValue(\.rdsGaussianTaps, odd, restartRequired: true)
            }
        )
    }

    func applyOrbassPreset(id: String) {
        guard let preset = Self.orbassPresets.first(where: { $0.id == id }) else { return }
        objectWillChange.send()
        config.orbassEnabled = preset.enabled
        config.orbassAmount = preset.amount
        config.orbassFreqHz = preset.freqHz
        config.orbassHarmonics = preset.harmonics
        config.orbassDrive = preset.drive
        config.orbassDensity = preset.density
        config.orbassSubharmonicsEnabled = preset.subharmonicsEnabled
        config.orbassSubharmonicsAmount = preset.subharmonicsAmount
        saveConfig(restartRequired: true)
        statusText =
            isRunning
            ? "Loaded Orbass preset \(preset.title). Press Apply to hear changes."
            : "Loaded Orbass preset \(preset.title)."
    }

    func applyMultibandPreset(id: String, intensity: MultibandPresetIntensity) {
        guard let preset = Self.multibandPresets.first(where: { $0.id == id }) else { return }
        objectWillChange.send()

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

        saveConfig(restartRequired: true)
        statusText =
            isRunning
            ? "Loaded Multiband preset \(preset.title) (\(intensity.title)). Press Apply to hear changes."
            : "Loaded Multiband preset \(preset.title) (\(intensity.title))."
    }

    func revealConfigInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: configPath)])
    }

    func reloadConfigFromDisk() {
        do {
            config = try AppConfig.load(fromINI: configPath)
            sourceMode = config.sourceMode
            monitorEnabled = config.monitorEnabled
            processingBypass = config.processingBypass
            inputGainDB = config.inputGainDB
            pendingRuntimeApply = false
            refreshDevices()
            statusText = "Config reloaded"
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
            applyPendingRuntimeChanges()
            statusText = "Reset to defaults"
        } catch {
            statusText = "Reset failed: \(error)"
        }
    }

    func resetProcessingToDefaults() {
        do {
            var defaults = AppConfig()
            defaults.sourceMode = sourceMode
            defaults.inputDeviceUID = selectedInputUID.isEmpty ? nil : selectedInputUID
            defaults.outputDeviceUID = selectedOutputUID.isEmpty ? nil : selectedOutputUID
            defaults.monitorEnabled = monitorEnabled
            defaults.monitorDeviceUID = selectedMonitorUID.isEmpty ? nil : selectedMonitorUID
            defaults.rdsAutoStart = config.rdsAutoStart
            defaults.enRDS = config.enRDS
            defaults.rdsPI = config.rdsPI
            defaults.rdsPSDynamic = config.rdsPSDynamic
            defaults.rdsPSCentered = config.rdsPSCentered
            defaults.rdsRTText = config.rdsRTText
            defaults.rdsRTA = config.rdsRTA
            defaults.rdsRTB = config.rdsRTB
            defaults.rdsPTYN = config.rdsPTYN
            defaults.rdsPTYNCentered = config.rdsPTYNCentered
            try defaults.save(toINI: configPath)
            config = defaults
            processingBypass = config.processingBypass
            inputGainDB = config.inputGainDB
            applyPendingRuntimeChanges()
            statusText = "Reset processing to defaults"
        } catch {
            statusText = "Reset failed: \(error)"
        }
    }

    func resetRDSToDefaults() {
        do {
            var defaults = AppConfig()
            defaults.sourceMode = sourceMode
            defaults.inputDeviceUID = selectedInputUID.isEmpty ? nil : selectedInputUID
            defaults.outputDeviceUID = selectedOutputUID.isEmpty ? nil : selectedOutputUID
            defaults.monitorEnabled = monitorEnabled
            defaults.monitorDeviceUID = selectedMonitorUID.isEmpty ? nil : selectedMonitorUID
            defaults.processingBypass = config.processingBypass
            defaults.inputGainDB = config.inputGainDB
            defaults.outputGainDB = config.outputGainDB
            defaults.preemphasisUS = config.preemphasisUS
            defaults.monoMode = config.monoMode
            defaults.widebandAGCEnabled = config.widebandAGCEnabled
            defaults.orbassEnabled = config.orbassEnabled
            defaults.multibandEnabled = config.multibandEnabled
            defaults.stereoWidenEnabled = config.stereoWidenEnabled
            defaults.limitMPX = config.limitMPX
            defaults.programLowpassHz = config.programLowpassHz
            defaults.diffLevel = config.diffLevel
            try defaults.save(toINI: configPath)
            config = defaults
            applyPendingRuntimeChanges()
            statusText = "Reset RDS to defaults"
        } catch {
            statusText = "Reset failed: \(error)"
        }
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

    private func restartEngineWithStatus(_ status: String) {
        let wasRunning = isRunning
        stopEngine()
        if wasRunning {
            startEngine()
            if isRunning {
                statusText = "\(status) and applied"
            }
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

        let generator = MPXGenerator(config: runConfig, sampleRate: runConfig.sampleRate)
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
        let minRefreshInterval = 1.0 / 60.0
        if let last = lastMonitorRefreshTime, (now - last) < minRefreshInterval {
            return
        }

        let dt = max(1.0 / 120.0, min(0.25, now - (lastMonitorRefreshTime ?? (now - (1.0 / 30.0)))))
        lastMonitorRefreshTime = now

        var inputPeak: Float = 0.0
        var inputLeftRMS: Float = 0.0
        var inputRightRMS: Float = 0.0
        var outputRMS: Float = 0.0
        var outputPeak: Float = 0.0
        var deviationKHz: Float = 0.0
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
            let hasCapture = cap.callbacks > 0
            inputPeak = hasCapture ? meters.inputPeak : meters.outputPeak
            inputLeftRMS = hasCapture ? meters.inputLeftRMS : meters.outputRMS
            inputRightRMS = hasCapture ? meters.inputRightRMS : meters.outputRMS
            outputRMS = meters.outputRMS
            outputPeak = meters.outputPeak
            deviationKHz = meters.deviationKHzPeak

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
            overflowHistory.removeAll(keepingCapacity: true)
            lastOverflowTotal = 0
            lastUnderflowTotal = 0
        }
        streamHealth = health

        let targetDeviation = Float(max(1.0, config.mpxDeviationKHz))
        let modulationNorm = max(0.0, min(2.0, deviationKHz / targetDeviation))
        let inputLTarget = Self.levelMeterScale(inputLeftRMS)
        let inputRTarget = Self.levelMeterScale(inputRightRMS)
        let outputTarget = Self.levelMeterScale(outputRMS)
        let modulationTarget = max(0.0, min(1.0, modulationNorm))

        vuInputL = smoothMeter(
            current: vuInputL, target: inputLTarget, dt: dt, attackMS: 18.0, releaseMS: 110.0)
        vuInputR = smoothMeter(
            current: vuInputR, target: inputRTarget, dt: dt, attackMS: 18.0, releaseMS: 110.0)
        vuOutput = smoothMeter(
            current: vuOutput, target: outputTarget, dt: dt, attackMS: 18.0, releaseMS: 110.0)
        vuModulation = smoothMeter(
            current: vuModulation, target: modulationTarget, dt: dt, attackMS: 18.0,
            releaseMS: 110.0)

        inputLLevel = Double(max(0.0, min(1.0, vuInputL)))
        inputRLevel = Double(max(0.0, min(1.0, vuInputR)))
        outputLevel = Double(max(0.0, min(1.0, vuOutput)))
        modulationLevel = Double(max(0.0, min(1.0, vuModulation)))

        // Sticky marker follows the same visual meter scale as the bar fill (RMS/VU style),
        // matching broadcast meter behavior and avoiding "marker above unreachable range".
        inputLPeakHoldLevel = Double(
            updatePeakHold(livePeak: vuInputL, state: &peakHoldInputL, dt: dt))
        inputRPeakHoldLevel = Double(
            updatePeakHold(livePeak: vuInputR, state: &peakHoldInputR, dt: dt))
        outputPeakHoldLevel = Double(
            updatePeakHold(livePeak: vuOutput, state: &peakHoldOutput, dt: dt))
        modulationPeakHoldLevel = Double(
            updatePeakHold(livePeak: vuModulation, state: &peakHoldModulation, dt: dt))

        inputLText = Self.dbfsString(inputLeftRMS)
        inputRText = Self.dbfsString(inputRightRMS)
        outputText = Self.meterMetaString(rms: outputRMS, peak: outputPeak)
        modulationText = String(format: "%.1f kHz", deviationKHz)

        let limiterState =
            config.compositeLimiterEnabled
            ? (outputPeak >= Float(config.limitThreshold) ? "Active" : "Idle") : "Off"
        limiterStateText = limiterState
        multibandStateText = config.multibandEnabled ? "On" : "Off"
        orbassStateText = config.orbassEnabled ? "On" : "Off"
        widenerStateText = config.stereoWidenEnabled ? "On" : "Off"

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
        spectrumQueue.async { [weak self] in
            let spectrum = Self.computeMPXSpectrum(
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

    nonisolated private static func computeMPXSpectrum(
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
        var signal = Array(samples.suffix(n))

        var mean: Float = 0.0
        vDSP_meanv(signal, 1, &mean, vDSP_Length(n))
        var negMean = -mean
        vDSP_vsadd(signal, 1, &negMean, &signal, 1, vDSP_Length(n))

        var window = Array(repeating: Float.zero, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        var windowed = Array(repeating: Float.zero, count: n)
        vDSP_vmul(signal, 1, window, 1, &windowed, 1, vDSP_Length(n))

        let fftLog2 = vDSP_Length(log2(Double(n)))
        guard let setup = vDSP_create_fftsetup(fftLog2, FFTRadix(kFFTRadix2)) else {
            return (Array(repeating: -100.0, count: safeBins), maxHz, nyquist)
        }
        defer { vDSP_destroy_fftsetup(setup) }

        var real = Array(repeating: Float.zero, count: n / 2)
        var imag = Array(repeating: Float.zero, count: n / 2)
        var magnitudesSq = Array(repeating: Float.zero, count: n / 2)

        real.withUnsafeMutableBufferPointer { realBP in
            imag.withUnsafeMutableBufferPointer { imagBP in
                var split = DSPSplitComplex(realp: realBP.baseAddress!, imagp: imagBP.baseAddress!)
                windowed.withUnsafeBufferPointer { src in
                    src.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                        complexSrc in
                        vDSP_ctoz(complexSrc, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, fftLog2, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudesSq, 1, vDSP_Length(n / 2))
            }
        }

        var spectrumDB = Array(repeating: Float(-100.0), count: n / 2)
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
        var mapped = Array(repeating: Float(-100.0), count: safeBins)
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
        let text: String
        if config.rdsRTManualBuffers {
            if config.rdsRTCycle {
                let cycle = max(1.0, config.rdsRTCycleTime)
                let idx = Int(elapsed / cycle) % 2
                text = idx == 0 ? config.rdsRTA : config.rdsRTB
            } else {
                text = config.rdsRTActiveBuffer == 0 ? config.rdsRTA : config.rdsRTB
            }
        } else {
            text = Self.currentTimedDisplayText(config.rdsRTText, elapsed: elapsed)
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
            id: "chr", title: "CHR/EDM", enabled: true, amount: 0.76, freqHz: 70, harmonics: 0.78,
            drive: 1.45, density: 0.86, subharmonicsEnabled: true, subharmonicsAmount: 0.55),
        .init(
            id: "urban", title: "Urban", enabled: true, amount: 0.72, freqHz: 68, harmonics: 0.74,
            drive: 1.35, density: 0.82, subharmonicsEnabled: true, subharmonicsAmount: 0.52),
        .init(
            id: "rock", title: "Rock", enabled: true, amount: 0.58, freqHz: 84, harmonics: 0.44,
            drive: 1.18, density: 0.72, subharmonicsEnabled: true, subharmonicsAmount: 0.34),
        .init(
            id: "ac", title: "AC/Pop", enabled: true, amount: 0.42, freqHz: 94, harmonics: 0.30,
            drive: 1.00, density: 0.66, subharmonicsEnabled: false, subharmonicsAmount: 0.20),
        .init(
            id: "talk", title: "Talk", enabled: true, amount: 0.22, freqHz: 118, harmonics: 0.16,
            drive: 0.72, density: 0.55, subharmonicsEnabled: false, subharmonicsAmount: 0.10),
    ]

    private static let multibandPresets: [MultibandPreset] = [
        .init(
            id: "3_chr", title: "3B CHR/EDM", mode: 3, lowHz: 260, highHz: 2300, x1Hz: nil,
            x2Hz: nil, x3Hz: nil, x4Hz: nil, lowThresholdDB: -25, lowRatio: 2.6, lowAttackMS: 18,
            lowReleaseMS: 290, midThresholdDB: -23, midRatio: 2.3, midAttackMS: 12,
            midReleaseMS: 220, highThresholdDB: -21, highRatio: 1.8, highAttackMS: 7,
            highReleaseMS: 150, kneeDB: 2.0, linkStrength: 0.36, releaseProgramDependent: true),
        .init(
            id: "3_rock", title: "3B Rock", mode: 3, lowHz: 290, highHz: 2400, x1Hz: nil, x2Hz: nil,
            x3Hz: nil, x4Hz: nil, lowThresholdDB: -23, lowRatio: 2.4, lowAttackMS: 20,
            lowReleaseMS: 310, midThresholdDB: -20, midRatio: 2.2, midAttackMS: 13,
            midReleaseMS: 230, highThresholdDB: -18, highRatio: 1.7, highAttackMS: 8,
            highReleaseMS: 165, kneeDB: 2.2, linkStrength: 0.40, releaseProgramDependent: true),
        .init(
            id: "3_ac", title: "3B AC/Pop", mode: 3, lowHz: 310, highHz: 2550, x1Hz: nil, x2Hz: nil,
            x3Hz: nil, x4Hz: nil, lowThresholdDB: -20, lowRatio: 2.0, lowAttackMS: 24,
            lowReleaseMS: 340, midThresholdDB: -18, midRatio: 1.8, midAttackMS: 16,
            midReleaseMS: 260, highThresholdDB: -17, highRatio: 1.4, highAttackMS: 10,
            highReleaseMS: 190, kneeDB: 2.8, linkStrength: 0.44, releaseProgramDependent: true),
        .init(
            id: "3_country", title: "3B Country", mode: 3, lowHz: 300, highHz: 2450, x1Hz: nil,
            x2Hz: nil, x3Hz: nil, x4Hz: nil, lowThresholdDB: -21, lowRatio: 2.2, lowAttackMS: 22,
            lowReleaseMS: 320, midThresholdDB: -19, midRatio: 1.9, midAttackMS: 15,
            midReleaseMS: 250, highThresholdDB: -17, highRatio: 1.5, highAttackMS: 10,
            highReleaseMS: 185, kneeDB: 2.6, linkStrength: 0.42, releaseProgramDependent: true),
        .init(
            id: "3_talk", title: "3B Talk", mode: 3, lowHz: 340, highHz: 3000, x1Hz: nil, x2Hz: nil,
            x3Hz: nil, x4Hz: nil, lowThresholdDB: -16, lowRatio: 1.6, lowAttackMS: 34,
            lowReleaseMS: 420, midThresholdDB: -15, midRatio: 1.5, midAttackMS: 28,
            midReleaseMS: 340, highThresholdDB: -14, highRatio: 1.3, highAttackMS: 18,
            highReleaseMS: 270, kneeDB: 3.8, linkStrength: 0.58, releaseProgramDependent: true),
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
            id: "5_chr", title: "5B CHR/EDM", mode: 5, lowHz: nil, highHz: nil, x1Hz: 80, x2Hz: 300,
            x3Hz: 1250, x4Hz: 5000, lowThresholdDB: -25, lowRatio: 2.8, lowAttackMS: 14,
            lowReleaseMS: 270, midThresholdDB: -23, midRatio: 2.4, midAttackMS: 10,
            midReleaseMS: 210, highThresholdDB: -21, highRatio: 1.9, highAttackMS: 5,
            highReleaseMS: 140, kneeDB: 1.8, linkStrength: 0.34, releaseProgramDependent: true),
        .init(
            id: "5_rock", title: "5B Rock", mode: 5, lowHz: nil, highHz: nil, x1Hz: 85, x2Hz: 320,
            x3Hz: 1400, x4Hz: 5400, lowThresholdDB: -23, lowRatio: 2.5, lowAttackMS: 18,
            lowReleaseMS: 300, midThresholdDB: -21, midRatio: 2.1, midAttackMS: 12,
            midReleaseMS: 225, highThresholdDB: -19, highRatio: 1.8, highAttackMS: 7,
            highReleaseMS: 160, kneeDB: 2.1, linkStrength: 0.38, releaseProgramDependent: true),
        .init(
            id: "5_ac", title: "5B AC/Pop", mode: 5, lowHz: nil, highHz: nil, x1Hz: 80, x2Hz: 320,
            x3Hz: 1500, x4Hz: 5800, lowThresholdDB: -20, lowRatio: 1.9, lowAttackMS: 22,
            lowReleaseMS: 330, midThresholdDB: -18, midRatio: 1.8, midAttackMS: 14,
            midReleaseMS: 260, highThresholdDB: -17, highRatio: 1.5, highAttackMS: 10,
            highReleaseMS: 190, kneeDB: 2.8, linkStrength: 0.44, releaseProgramDependent: true),
        .init(
            id: "5_classic", title: "5B Classical/Jazz", mode: 5, lowHz: nil, highHz: nil, x1Hz: 90,
            x2Hz: 360, x3Hz: 1700, x4Hz: 6500, lowThresholdDB: -17, lowRatio: 1.5, lowAttackMS: 36,
            lowReleaseMS: 450, midThresholdDB: -16, midRatio: 1.4, midAttackMS: 30,
            midReleaseMS: 360, highThresholdDB: -15, highRatio: 1.25, highAttackMS: 20,
            highReleaseMS: 280, kneeDB: 4.5, linkStrength: 0.60, releaseProgramDependent: true),
        .init(
            id: "5_talk", title: "5B Talk", mode: 5, lowHz: nil, highHz: nil, x1Hz: 100, x2Hz: 400,
            x3Hz: 1800, x4Hz: 7000, lowThresholdDB: -16, lowRatio: 1.5, lowAttackMS: 38,
            lowReleaseMS: 480, midThresholdDB: -15, midRatio: 1.4, midAttackMS: 32,
            midReleaseMS: 380, highThresholdDB: -14, highRatio: 1.2, highAttackMS: 22,
            highReleaseMS: 300, kneeDB: 4.2, linkStrength: 0.62, releaseProgramDependent: true),
        .init(
            id: "5_urban", title: "5B Urban", mode: 5, lowHz: nil, highHz: nil, x1Hz: 75, x2Hz: 280,
            x3Hz: 1100, x4Hz: 4700, lowThresholdDB: -24, lowRatio: 2.7, lowAttackMS: 14,
            lowReleaseMS: 270, midThresholdDB: -22, midRatio: 2.3, midAttackMS: 10,
            midReleaseMS: 205, highThresholdDB: -20, highRatio: 1.9, highAttackMS: 5,
            highReleaseMS: 140, kneeDB: 1.9, linkStrength: 0.36, releaseProgramDependent: true),
        .init(
            id: "5_dance", title: "5B Dance", mode: 5, lowHz: nil, highHz: nil, x1Hz: 70, x2Hz: 260,
            x3Hz: 1000, x4Hz: 4300, lowThresholdDB: -26, lowRatio: 3.0, lowAttackMS: 12,
            lowReleaseMS: 250, midThresholdDB: -24, midRatio: 2.6, midAttackMS: 9,
            midReleaseMS: 190, highThresholdDB: -22, highRatio: 2.1, highAttackMS: 4,
            highReleaseMS: 130, kneeDB: 1.7, linkStrength: 0.32, releaseProgramDependent: true),
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
                statusText = "Config updated. Press Apply in Monitoring to hear changes."
            }
            pendingRuntimeApply = true
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
        peakHoldInputL = PeakHoldState()
        peakHoldInputR = PeakHoldState()
        peakHoldOutput = PeakHoldState()
        peakHoldModulation = PeakHoldState()
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

    private func smoothMeter(
        current: Float, target: Float, dt: Double, attackMS: Float, releaseMS: Float
    ) -> Float {
        let clampedTarget = max(0.0, min(1.0, target.isFinite ? target : 0.0))
        let tauMS = clampedTarget >= current ? max(1.0, attackMS) : max(5.0, releaseMS)
        let alpha = 1.0 - exp(-dt / (Double(tauMS) * 0.001))
        return current + ((clampedTarget - current) * Float(alpha))
    }

    private static func levelMeterScale(_ linear: Float) -> Float {
        let safeLinear = max(1e-9, linear.isFinite ? linear : 0.0)
        let db = 20.0 * log10f(safeLinear)
        let floorDB: Float = -36.0
        let curve: Float = 0.88
        let norm = max(0.0, min(1.0, (db - floorDB) / -floorDB))
        return powf(norm, curve)
    }

    private static func dbfsString(_ linear: Float) -> String {
        guard linear > 1e-9 else { return "-inf dBFS" }
        let db = 20.0 * log10(Double(linear))
        return String(format: "%.1f dBFS", db)
    }

    private static func meterMetaString(rms: Float, peak: Float) -> String {
        let rmsString = dbfsString(rms)
        let peakDB = peak > 1e-9 ? (20.0 * log10(Double(peak))) : -120.0
        return "\(rmsString)   \(String(format: "%.1f", peakDB)) pk"
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
            .frame(width: 220)

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
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Input") {
                            Text(inputName)
                        }
                        LabeledContent("Output") {
                            Text(outputName)
                        }
                    }
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
}

private struct MonitoringTransportHeader: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        HStack(spacing: 12) {
            Spacer()

            if model.runtimeApplyPending {
                Button("Apply") {
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
    @State private var expanded: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(spacing: 6) {
                LabeledContent("Ring") { Text(ringText).textSelection(.enabled) }
                LabeledContent("Overflows (10s)") { Text("\(health.overflowsRecent)") }
                LabeledContent("Underflows (10s)") { Text("\(health.underflowsRecent)") }
                LabeledContent("Totals") { Text("O:\(health.overflowsTotal) U:\(health.underflowsTotal)") }
                LabeledContent("Rates") { Text(rateText) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 6)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(indicatorColor)

                Text(health.isRunning ? "Running" : "Stopped")
                    .font(.body.weight(.medium))

                Text("• Buffer \(health.bufferSummary)")
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
        }
        .disclosureGroupStyle(.automatic)
        .padding(.vertical, 2)
    }

    private var summaryText: String {
        let stateText = health.isRunning ? "Running" : "Stopped"
        return
            "\(stateText) • \(health.rateSummary) • Input: \(health.inputName) • Buffer: \(health.bufferSummary)"
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

    private var indicatorColor: Color {
        guard health.isRunning else { return .secondary }
        switch health.bufferHealth {
        case .ok:
            return .green
        case .warn:
            return .yellow
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Live view").font(.subheadline).foregroundStyle(.secondary)
            KeyValueGrid(rows: model.rdsRows)
        }
    }
}

private struct MonitoringLevelsSectionView: View {
    @ObservedObject var model: StereoFoolViewModel
    private let holdOptions: [Double] = [0.5, 1.0, 1.5, 2.0, 3.0]
    private let fallOptions: [Double] = [6.0, 12.0, 18.0, 24.0, 30.0]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Levels").font(.headline)

            LabeledContent("Input Gain") {
                HStack(spacing: 12) {
                    Slider(
                        value: Binding(
                            get: { model.inputGainDB },
                            set: {
                                model.inputGainDB = $0
                                model.persistBasicConfig()
                            }
                        ), in: -24...24)
                    Text(String(format: "%.1f dB", model.inputGainDB))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .trailing)
                }
            }

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
                .frame(width: 100)
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
                .frame(width: 110)
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
                peakLevel: model.modulationPeakHoldLevel, showsDBScale: false)
        }
    }
}

private struct MonitoringDSPStatusSectionView: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DSP Status").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                DSPStateIndicator(
                    title: "Composite Limiter",
                    dotColor: Self.compositeLimiterDotColor(for: model.limiterStateText)
                )
                DSPStateIndicator(
                    title: "Multiband",
                    dotColor: model.multibandStateText.caseInsensitiveCompare("On") == .orderedSame
                        ? .green : .secondary.opacity(0.45)
                )
                DSPStateIndicator(
                    title: "Orbass",
                    dotColor: model.orbassStateText.caseInsensitiveCompare("On") == .orderedSame
                        ? .green : .secondary.opacity(0.45)
                )
                DSPStateIndicator(
                    title: "Widener",
                    dotColor: model.widenerStateText.caseInsensitiveCompare("On") == .orderedSame
                        ? .green : .secondary.opacity(0.45)
                )
                Spacer(minLength: 0)
            }
            .font(.callout)
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
                    TextField("", text: model.hexByteBinding(\.rdsLIC))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 80)
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
                LabeledContent("Input Gain") {
                    HStack(spacing: 12) {
                        Slider(
                            value: Binding(
                                get: { model.inputGainDB },
                                set: {
                                    model.inputGainDB = $0
                                    model.persistBasicConfig()
                                }
                            ), in: -24...24)
                        Text(String(format: "%.1f dB", model.inputGainDB))
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .trailing)
                    }
                }

                Divider()
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
                    showsDBScale: false)
            }
            .controlSize(.regular)
        }
    }
}

private struct MeterRow: View {
    let label: String
    let valueText: String
    let level: Double
    let peakLevel: Double?
    let showsDBScale: Bool

    init(
        label: String, valueText: String, level: Double, peakLevel: Double? = nil,
        showsDBScale: Bool = false
    ) {
        self.label = label
        self.valueText = valueText
        self.level = level
        self.peakLevel = peakLevel
        self.showsDBScale = showsDBScale
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
            MeterBar(level: level, peakLevel: peakLevel, showsDBScale: showsDBScale)
        }
        .font(.callout)
    }
}

private struct MeterBar: View {
    let level: Double
    let peakLevel: Double?
    let showsDBScale: Bool

    private let scaleTicks: [Double] = [0.0, 0.33, 0.66, 0.83, 0.92, 1.0]
    private let scaleLabels: [String] = ["-36", "-24", "-12", "-6", "-3", "0 dBFS"]

    private var meterTint: Color {
        if level >= 0.92 { return .red }
        if level >= 0.83 { return .orange }
        if level >= 0.66 { return .yellow }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                let width = max(0.0, min(1.0, level)) * geo.size.width
                let peakX = (peakLevel.map { max(0.0, min(1.0, $0)) } ?? 0.0) * geo.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.secondary.opacity(0.18))
                    ForEach(scaleTicks, id: \.self) { tick in
                        Rectangle()
                            .fill(Color.primary.opacity(0.15))
                            .frame(width: 1)
                            .offset(x: (tick * geo.size.width) - 0.5)
                    }
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(meterTint.opacity(0.75))
                        .frame(width: max(0.0, width))
                    if peakLevel != nil {
                        Rectangle()
                            .fill(Color.primary.opacity(0.98))
                            .frame(width: 2, height: 14)
                            .offset(x: min(max(0.0, peakX - 1.0), max(0.0, geo.size.width - 2.0)))
                    }
                }
            }
            .frame(height: 14)
            if showsDBScale {
                HStack {
                    ForEach(Array(scaleLabels.enumerated()), id: \.offset) { idx, title in
                        Text(title)
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                        if idx < scaleLabels.count - 1 {
                            Spacer(minLength: 0)
                        }
                    }
                }
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
            VStack(alignment: .leading, spacing: 10) {
                DSPStateIndicator(
                    title: "Composite Limiter",
                    dotColor: MonitoringDSPStatusSectionView.compositeLimiterDotColor(
                        for: model.limiterStateText)
                )
                HStack(spacing: 10) {
                    DSPStateIndicator(
                        title: "Multiband",
                        dotColor: model.multibandStateText.caseInsensitiveCompare("On")
                            == .orderedSame ? .green : .secondary.opacity(0.45)
                    )
                    DSPStateIndicator(
                        title: "Orbass",
                        dotColor: model.orbassStateText.caseInsensitiveCompare("On") == .orderedSame
                            ? .green : .secondary.opacity(0.45)
                    )
                    DSPStateIndicator(
                        title: "Widener",
                        dotColor: model.widenerStateText.caseInsensitiveCompare("On")
                            == .orderedSame ? .green : .secondary.opacity(0.45)
                    )
                }
            }
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
                        Button("Reset Processing to Defaults") {
                            model.resetProcessingToDefaults()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(20)
                .frame(maxWidth: 800, alignment: .topLeading)
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
            Picker("Pre-emphasis", selection: model.configBinding(\.preemphasisUS)) {
                Text("Off").tag(0)
                Text("50 us").tag(50)
                Text("75 us").tag(75)
            }
            .pickerStyle(.segmented)
            DoubleSliderRow(title: "Input Gain", value: Binding(
                get: { model.inputGainDB },
                set: {
                    model.inputGainDB = $0
                    model.persistBasicConfig()
                }
            ), range: -24...24, format: "%.1f dB")
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
            Toggle("Enable Wideband AGC", isOn: model.configBinding(\.widebandAGCEnabled))
            DoubleSliderRow(title: "Target", value: model.configBinding(\.widebandAGCTargetDB), range: -36 ... -6, format: "%.1f dB")
            DoubleSliderRow(title: "Attack", value: model.configBinding(\.widebandAGCAttackMS), range: 1...150, format: "%.1f ms")
            DoubleSliderRow(title: "Release", value: model.configBinding(\.widebandAGCReleaseMS), range: 40...1200, format: "%.1f ms")
            DoubleSliderRow(title: "Max Gain", value: model.configBinding(\.widebandAGCMaxGainDB), range: 0...24, format: "%.1f dB")
            DoubleSliderRow(title: "Min Gain", value: model.configBinding(\.widebandAGCMinGainDB), range: -24...0, format: "%.1f dB")
        }
    }
}

private struct ProcessingOrbassTab: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        Card(title: "Orbass") {
            Toggle("Enable Orbass", isOn: model.configBinding(\.orbassEnabled))
            DoubleSliderRow(title: "Amount", value: model.configBinding(\.orbassAmount), range: 0...1.2, format: "%.2f")
            DoubleSliderRow(title: "Frequency", value: model.configBinding(\.orbassFreqHz), range: 40...180, format: "%.1f Hz")
            DoubleSliderRow(title: "Harmonics", value: model.configBinding(\.orbassHarmonics), range: 0...1.2, format: "%.2f")
            DoubleSliderRow(title: "Drive", value: model.configBinding(\.orbassDrive), range: 0.2...2.0, format: "%.2f")
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
            Toggle("Enable Multiband", isOn: model.configBinding(\.multibandEnabled))
            Picker("Mode", selection: model.configBinding(\.multibandMode)) {
                Text("2-band").tag(2)
                Text("3-band").tag(3)
                Text("5-band").tag(5)
            }
            DoubleSliderRow(title: "Knee", value: model.configBinding(\.multibandKneeDB), range: 0...12, format: "%.1f dB")
            DoubleSliderRow(title: "Link", value: model.configBinding(\.multibandLinkStrength), range: 0...1, format: "%.2f")
            Toggle("Program-dependent Release", isOn: model.configBinding(\.multibandReleaseProgramDependent))
            DoubleSliderRow(title: "X1", value: model.configBinding(\.multibandX1Hz), range: 30...300, format: "%.0f Hz")
            DoubleSliderRow(title: "X2", value: model.configBinding(\.multibandX2Hz), range: 120...1200, format: "%.0f Hz")
            DoubleSliderRow(title: "X3", value: model.configBinding(\.multibandX3Hz), range: 600...4000, format: "%.0f Hz")
            DoubleSliderRow(title: "X4", value: model.configBinding(\.multibandX4Hz), range: 2500...12000, format: "%.0f Hz")
            DoubleSliderRow(title: "Low Threshold", value: model.configBinding(\.multibandLowThresholdDB), range: (-40)...(-6), format: "%.1f dB")
            DoubleSliderRow(title: "Mid Threshold", value: model.configBinding(\.multibandMidThresholdDB), range: (-40)...(-6), format: "%.1f dB")
            DoubleSliderRow(title: "High Threshold", value: model.configBinding(\.multibandHighThresholdDB), range: (-40)...(-6), format: "%.1f dB")
            DoubleSliderRow(title: "Low Ratio", value: model.configBinding(\.multibandLowRatio), range: 1...8, format: "%.2f")
            DoubleSliderRow(title: "Mid Ratio", value: model.configBinding(\.multibandMidRatio), range: 1...8, format: "%.2f")
            DoubleSliderRow(title: "High Ratio", value: model.configBinding(\.multibandHighRatio), range: 1...8, format: "%.2f")
            DoubleSliderRow(title: "Low Attack", value: model.configBinding(\.multibandLowAttackMS), range: 1...120, format: "%.1f")
            DoubleSliderRow(title: "Mid Attack", value: model.configBinding(\.multibandMidAttackMS), range: 1...120, format: "%.1f")
            DoubleSliderRow(title: "High Attack", value: model.configBinding(\.multibandHighAttackMS), range: 1...120, format: "%.1f")
            DoubleSliderRow(title: "Low Release", value: model.configBinding(\.multibandLowReleaseMS), range: 40...1200, format: "%.0f")
            DoubleSliderRow(title: "Mid Release", value: model.configBinding(\.multibandMidReleaseMS), range: 40...1200, format: "%.0f")
            DoubleSliderRow(title: "High Release", value: model.configBinding(\.multibandHighReleaseMS), range: 40...1200, format: "%.0f")
            DoubleSliderRow(title: "Makeup", value: model.configBinding(\.multibandMakeupDB), range: -12...18, format: "%.1f dB")
        }
    }
}

private struct ProcessingWidenerTab: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        Card(title: "Stereo Widener") {
            Toggle("Enable Stereo Widener", isOn: model.configBinding(\.stereoWidenEnabled))
            DoubleSliderRow(title: "Width", value: model.configBinding(\.stereoWidenWidth), range: 0...1, format: "%.2f")
            DoubleSliderRow(title: "Center", value: model.configBinding(\.stereoWidenCenter), range: 0...1, format: "%.2f")
            DoubleSliderRow(title: "Mix", value: model.configBinding(\.stereoWidenMix), range: 0...1, format: "%.2f")
        }
    }
}

private struct ProcessingLimiterTab: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        Card(title: "Composite Limiter") {
            Toggle("Enable Composite Limiter", isOn: model.configBinding(\.compositeLimiterEnabled))
            DoubleSliderRow(title: "Composite Deviation", value: model.configBinding(\.mpxDeviationKHz), range: 40...90, format: "%.1f kHz")
        }
    }
}

private struct LevelsOnlyView: View {
    @ObservedObject var model: StereoFoolViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                LevelsCardView(model: model)
            }
            .padding(20)
        }
    }
}

private struct SystemSettingsSectionContent: View {
    @ObservedObject var model: StereoFoolViewModel

    private let sampleRates: [Double] = [44_100, 48_000, 88_200, 96_000, 176_400, 192_000]
    private let blockSizes: [Int] = [2048, 4096, 8192]

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
                isOn: model.configBinding(\.rdsAutoStart, restartRequired: false))

            Toggle("Mono Mode", isOn: model.configBinding(\.monoMode))

            DoubleSliderRow(
                title: "Pilot Level", value: model.configBinding(\.pilotLevel),
                range: 0...0.2, format: "%.3f")
            DoubleSliderRow(
                title: "Sum Level", value: model.configBinding(\.sumLevel),
                range: 0...1.5, format: "%.2f")
            DoubleSliderRow(
                title: "Diff Level", value: model.configBinding(\.diffLevel),
                range: 0...1.5, format: "%.2f")
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
                        Button("Reset RDS to Defaults") {
                            model.resetRDSToDefaults()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(20)
                .frame(maxWidth: 800, alignment: .topLeading)
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
                TextField("", text: model.piBinding())
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 90)
            }
            LabeledContent("ECC") {
                TextField("", text: model.hexByteBinding(\.rdsECC))
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 80)
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
            TextField("RT+ Format A", text: model.configBinding(\.rdsRTPlusFormatA))
            TextField("RT+ Format B", text: model.configBinding(\.rdsRTPlusFormatB))
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
                TextField("", text: model.hexByteBinding(\.rdsLIC))
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 80)
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
        .frame(maxWidth: 720, alignment: .topLeading)
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
        NavigationSplitView {
            List(HelpTopic.allCases, selection: $selection) { topic in
                Label(topic.rawValue, systemImage: topic.icon)
                    .symbolRenderingMode(.hierarchical)
                    .tag(topic)
            }
            .listStyle(.sidebar)
            .navigationTitle("Help")
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch selection {
                    case .inputLevels:
                        HelpInputLevelsView()
                    case .rdsText:
                        HelpRDSTextView()
                    }
                }
                .padding(20)
                .frame(maxWidth: 640, alignment: .leading)
            }
            .navigationTitle(selection.rawValue)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbarTitleDisplayMode(.inline)
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

private struct HelpInputLevelsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recommended targets for FM broadcast alignment.")
                .foregroundStyle(.secondary)
                .font(.callout)

            GroupBox {
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Peak")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("-18 to -6 dBFS")
                            .font(.body.weight(.semibold))
                    }
                    Divider().frame(height: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Average (RMS)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("-24 to -20 dBFS")
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
                Text("• US nominal: -20 dBFS")
                Text("• Europe (EBU R68): -18 dBFS")
                Text("• Very hot chains may peak near -6 dBFS")
                Text("If you hit 0 dBFS, reduce input gain and re-check pre-emphasis behavior.")
            }
            .foregroundStyle(.secondary)
            .font(.callout)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: 640, alignment: .leading)
    }
}

private struct HelpRDSTextView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timed text sequences for PS and Radiotext.")
                .foregroundStyle(.secondary)
                .font(.callout)

            Text("Syntax")
                .font(.headline)
                .padding(.top, 4)

            CodeBlock("10s:First/10s:Second")

            Text("Shows \"First\" for 10 seconds, then \"Second\" for 10 seconds, repeating.")
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

            Spacer(minLength: 0)
        }
        .frame(maxWidth: 640, alignment: .leading)
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
