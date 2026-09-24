import AppKit
import SwiftUI
import MacZCore

@main
struct MacZApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private var model: AppModel { delegate.model }

    init() {
        if CommandLine.arguments.contains("--report") {
            let sampler = Sampler()
            _ = sampler.sample()
            Thread.sleep(forTimeInterval: 0.2)
            print(Hardware.read().report(metrics: sampler.sample()), terminator: "")
            exit(0)
        }
    }

    var body: some Scene {
        Window("MacZ", id: "main") {
            ContentView(model: model)
        }
        .defaultSize(width: 720, height: 640)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .pasteboard) {
                Button("Copy System Report") { model.copyReport() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = AppIcon.image
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged),
                                               name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        model.startSampling()
    }
    @objc private func occlusionChanged(_ notification: Notification) {
        model.windowVisible = NSApp.windows.contains { $0.canBecomeMain && $0.occlusionState.contains(.visible) }
    }
    @objc private func willSleep(_ notification: Notification) { model.setSleeping(true) }
    @objc private func didWake(_ notification: Notification) { model.setSleeping(false) }
    func applicationWillTerminate(_ notification: Notification) { model.stopSampling() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor
enum AppIcon {
    static let image: NSImage = {
        // The app bundle serves Finder; the SwiftPM resource also supports `swift run`.
        let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            ?? Bundle.module.url(forResource: "AppIcon", withExtension: "icns")
        guard let url, let image = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "cpu", accessibilityDescription: "MacZ")!
        }
        return image
    }()
}

@MainActor
final class AppModel: ObservableObject {
    let hardware = Hardware.read()
    private let sampler = Sampler()
    // Sampling continues for the Dock while the window is hidden, but only a visible window re-renders.
    var metrics: Metrics? { willSet { publishIfVisible() } }
    var cpuHistory: [Double?] = [] { willSet { publishIfVisible() } }
    var memoryHistory: [Double?] = [] { willSet { publishIfVisible() } }
    var windowVisible = true {
        didSet { if windowVisible && !oldValue { objectWillChange.send() } }
    }
    @Published var paused = false {
        didSet {
            guard paused != oldValue else { return }
            if paused { stopSampling() } else { startSampling() }
            updateDock()
        }
    }
    @Published var copied = false
    @Published var copyFailed = false
    private var copyReset: Task<Void, Never>?
    private var samplingTask: Task<Void, Never>?
    private(set) var samplingActivity: NSObjectProtocol?
    private var lastSampleTime: ContinuousClock.Instant?
    private var sleeping = false
    private(set) var dockHistory = DockHistory()
    private let dockView = DockHistoryView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))

    func startSampling() {
        guard !paused, !sleeping, samplingTask == nil else { return }
        sampler.resetCPU()
        lastSampleTime = nil
        dockHistory.reset()
        cpuHistory.removeAll()
        memoryHistory.removeAll()
        NSApp.dockTile.contentView = dockView
        // Keep the user-requested Dock monitor updating while allowing system sleep.
        samplingActivity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep, reason: "Update CPU and GPU readings in the Dock")
        sample()
        samplingTask = Task { [weak self] in
            let clock = ContinuousClock()
            var deadline = clock.now.advanced(by: .seconds(2))
            while !Task.isCancelled {
                do { try await clock.sleep(until: deadline, tolerance: .milliseconds(100)) } catch { return }
                guard !Task.isCancelled, let self else { return }
                self.sample()
                deadline = deadline.advanced(by: .seconds(2))
                // Never issue a burst of catch-up samples after a delayed callback.
                if deadline <= clock.now { deadline = clock.now.advanced(by: .seconds(2)) }
            }
        }
    }

    func stopSampling() {
        samplingTask?.cancel()
        samplingTask = nil
        if let samplingActivity { ProcessInfo.processInfo.endActivity(samplingActivity) }
        samplingActivity = nil
        sampler.resetCPU()
        lastSampleTime = nil
    }

    func setSleeping(_ sleeping: Bool) {
        self.sleeping = sleeping
        if sleeping { stopSampling() } else { startSampling() }
    }

    func sample(at now: ContinuousClock.Instant = .now) {
        if let lastSampleTime, lastSampleTime.duration(to: now) > .seconds(3) {
            // A suspended process may miss notifications. Do not label old data as live history.
            sampler.resetCPU()
            dockHistory.reset()
            cpuHistory.removeAll()
            memoryHistory.removeAll()
        }
        lastSampleTime = now
        metrics = sampler.sample()
        cpuHistory = Array((cpuHistory + [metrics?.cpu?.total]).suffix(60))
        memoryHistory = Array((memoryHistory + [metrics?.memory.map { $0.fraction * 100 }]).suffix(60))
        dockHistory.append(cpu: metrics?.cpu?.total, gpu: metrics?.gpu)
        updateDock()
    }

    private func publishIfVisible() {
        if windowVisible { objectWillChange.send() }
    }

    private func updateDock() {
        dockView.show(dockHistory, paused: paused)
        NSApp.dockTile.badgeLabel = paused ? "Paused" : nil
        NSApp.dockTile.display()
    }

    func copyReport(using write: (String) -> Bool = { report in
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(report, forType: .string)
    }) {
        copyReset?.cancel()
        copied = write(hardware.report(metrics: metrics, paused: paused))
        copyFailed = !copied
        guard copied else { return }
        copyReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.copied = false
        }
    }
}
