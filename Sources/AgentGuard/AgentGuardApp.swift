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
    private var scanTimer: Timer?
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

        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performScan()
            }
        }

        scanTimer = Timer.scheduledTimer(withTimeInterval: currentScanInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performScan()
            }
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
        }
    }

    func showSettings() {
        // Close popover if open
        if popover.isShown { popover.performClose(nil) }

        // Reuse existing window or create new one
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "AgentGuard Settings"
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        // Show in Dock while settings is open, hide when closed
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        settingsWindow = window

        // Watch for window close to hide from Dock again
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
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

    private func performScan() async {
        guard !state.isScanning else { return }

        state.isScanning = true
        updateMenuBarIcon()

        let result = await scanner.runFullScan()

        state.lastScanDate = result.scanDate
        state.mcpResult = result.mcp
        state.skillResult = result.skill
        state.scannerInfo = ScannerInfo(
            mcpScannerVersion: result.mcpScannerVersion,
            skillScannerVersion: result.skillScannerVersion,
            skillScannerInstalled: result.skillScannerInstalled
        )
        state.isScanning = false

        let newInterval = TimeInterval(result.scanInterval * 60)
        if newInterval != currentScanInterval {
            currentScanInterval = newInterval
            scanTimer?.invalidate()
            scanTimer = Timer.scheduledTimer(withTimeInterval: currentScanInterval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.performScan()
                }
            }
        }

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
}
