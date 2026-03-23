import Cocoa
import SwiftUI

// MARK: - Menu bar icon as SwiftUI view (Stats/eul pattern — most reliable)

struct MenuBarIconView: View {
    let count: Int
    let isScanning: Bool

    private var iconName: String {
        if isScanning { return "shield.lefthalf.filled" }
        if count > 0 { return "exclamationmark.shield.fill" }
        return "checkmark.shield.fill"
    }

    private var iconColor: Color {
        if isScanning { return .secondary }
        if count > 0 { return Color(hex: "#FF4444") }
        return Color(hex: "#44BB44")
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(iconColor)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
        .frame(height: 22)
        .fixedSize()
    }
}

// MARK: - Click-through hosting view (passes mouse events to parent button)

class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

// MARK: - AppDelegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var statusView: ClickThroughHostingView<MenuBarIconView>?
    private var settingsWindow: NSWindow?
    private let state = ScanState()
    private let scanner = ScannerService()
    private let deps = DependencyManager()
    private var currentScanInterval: TimeInterval = 300

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            self.setup()
        }
    }

    // When user opens the app again (Spotlight, Finder, Dock) — show Settings
    nonisolated func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in
            self.showSettings()
        }
        return false
    }

    private func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self

            let hostingView = ClickThroughHostingView(rootView: MenuBarIconView(count: 0, isScanning: true))
            hostingView.frame = NSRect(x: 0, y: 0, width: 24, height: 22)
            button.addSubview(hostingView)
            button.frame = hostingView.frame
            statusItem.length = 24
            statusView = hostingView
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 460)
        popover.behavior = .transient
        popover.animates = true
        setupPopoverContent()

        // Ensure dependencies then scan, all async
        Task { [weak self] in
            await self?.deps.ensureDependencies()
            await self?.performScan()
            await self?.startPeriodicScan()
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            popover.contentViewController?.view.window?.makeFirstResponder(popover.contentViewController?.view)

            // Auto-screenshot popover for UI validation (debug builds only)
            #if DEBUG
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                if let url = ScreenshotValidator.capturePopover(self.popover, label: "popover") {
                    self.debugLog("Screenshot saved: \(url.path)")
                }
            }
            #endif
        }
    }

    private var hasActivatedBefore = false

    func showSettings() {
        if popover.isShown { popover.performClose(nil) }

        // Create window if needed
        if settingsWindow == nil {
            let hostingController = NSHostingController(rootView: SettingsView())
            let w = NSWindow(contentViewController: hostingController)
            w.title = "AgentGuard Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 420, height: 480))
            w.setFrameAutosaveName("AgentGuardSettings")
            settingsWindow = w
            setupSettingsWindowCloseHandler(w)
        }

        guard let window = settingsWindow else { return }

        // Center using visibleFrame (true center, not Apple's upper-third)
        // Only if no saved position from previous session
        if !window.setFrameUsingName("AgentGuardSettings") {
            if let screen = NSScreen.main {
                let vis = screen.visibleFrame
                let x = vis.midX - window.frame.width / 2
                let y = vis.midY - window.frame.height / 2
                window.setFrameOrigin(NSPoint(x: x, y: y))
            }
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)

        // Ice-style: first activation from .accessory needs Dock hack
        if !hasActivatedBefore {
            hasActivatedBefore = true
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApp.activate(ignoringOtherApps: true)
            }
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func setupSettingsWindowCloseHandler(_ window: NSWindow) {
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.settingsWindow = nil
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    private func setupPopoverContent() {
        let view = PopoverView(
            state: state,
            onScanNow: { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.performScan()
                }
            },
            onIgnore: { [weak self] key in
                Task { @MainActor [weak self] in
                    await self?.scanner.addIgnore(key)
                    await self?.refreshIgnoreState()
                }
            },
            onRestore: { [weak self] key in
                Task { @MainActor [weak self] in
                    await self?.scanner.removeIgnore(key)
                    await self?.refreshIgnoreState()
                }
            },
            onSettings: { [weak self] in
                self?.showSettings()
            },
            onQuit: {
                NSApplication.shared.terminate(nil)
            }
        )
        popover.contentViewController = NSHostingController(rootView: view)
    }

    private func startPeriodicScan() {
        Task { [weak self] in
            while let self {
                try? await Task.sleep(nanoseconds: UInt64(self.currentScanInterval) * 1_000_000_000)
                await self.performScan()
            }
        }
    }

    private func performScan() async {
        guard !state.isScanning else { return }

        let logFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/mcp-scan/agentguard.log")

        state.isScanning = true
        updateMenuBarIcon()

        try? "[\(Date())] Scan starting...\n".write(to: logFile, atomically: true, encoding: .utf8)

        let result = await scanner.runFullScan()

        let log = """
        [\(Date())] Scan complete:
          MCP: \(result.mcp.configCount) configs, \(result.mcp.toolCount) tools, \(result.mcp.serverCount) servers, \(result.mcp.findings.count) findings
          Skills: \(result.skill.skillCount) skills, \(result.skill.findings.count) findings, \(result.skill.safeSkills.count) safe
          Scanners: mcp=\(result.mcpScannerVersion) skill=\(result.skillScannerVersion) installed=\(result.skillScannerInstalled)
          Interval: \(result.scanInterval)m\n
        """
        try? log.write(to: logFile, atomically: true, encoding: .utf8)

        state.lastScanDate = result.scanDate
        state.mcpResult = result.mcp
        state.skillResult = result.skill
        state.scannerInfo = ScannerInfo(
            mcpScannerVersion: result.mcpScannerVersion,
            skillScannerVersion: result.skillScannerVersion,
            skillScannerInstalled: result.skillScannerInstalled
        )
        state.isScanning = false
        currentScanInterval = TimeInterval(result.scanInterval * 60)

        updateMenuBarIcon()
    }

    private func refreshIgnoreState() async {
        let ignored = await scanner.loadIgnoreList()
        var mcpFindings = state.mcpFindings
        for i in mcpFindings.indices {
            mcpFindings[i].isIgnored = ignored.contains(mcpFindings[i].key)
        }
        state.mcpFindings = mcpFindings

        var skillFindings = state.skillFindings
        for i in skillFindings.indices {
            skillFindings[i].isIgnored = ignored.contains(skillFindings[i].key)
        }
        state.skillFindings = skillFindings

        updateMenuBarIcon()
    }

    private func updateMenuBarIcon() {
        let count = state.totalActiveCount
        let iconView = MenuBarIconView(count: count, isScanning: state.isScanning)
        statusView?.rootView = iconView

        let width = max(24, (statusView?.fittingSize.width ?? 24) + 8)
        statusView?.frame = NSRect(x: 0, y: 0, width: width, height: 22)
        statusItem.button?.frame = statusView?.frame ?? NSRect(x: 0, y: 0, width: width, height: 22)
        statusItem.length = width
    }

    #if DEBUG
    private func debugLog(_ msg: String) {
        let logFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/mcp-scan/agentguard.log")
        let line = "[\(Date())] [debug] \(msg)\n"
        if let data = line.data(using: .utf8),
           let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }
    }
    #endif
}
