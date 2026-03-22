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
        // Return nil so the parent NSStatusBarButton receives the click
        return nil
    }
}

// MARK: - AppDelegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var statusView: ClickThroughHostingView<MenuBarIconView>?
    private let state = ScanState()
    private let scanner = ScannerService()
    private var scanTimer: Timer?
    private var currentScanInterval: TimeInterval = 300

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            self.setup()
        }
    }

    private func setup() {
        // Start with enough space, will resize dynamically
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self

            // Embed SwiftUI view as subview (like Stats/eul)
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

        // Initial scan
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performScan()
            }
        }

        // Periodic scan
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
            // Activate app first so the popover window can become key
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Ensure the popover window accepts clicks
            popover.contentViewController?.view.window?.makeKey()
            popover.contentViewController?.view.window?.makeFirstResponder(popover.contentViewController?.view)
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
            onQuit: {
                NSApplication.shared.terminate(nil)
            }
        )
        popover.contentViewController = NSHostingController(rootView: view)
    }

    private func performScan() async {
        // Fix #1: Prevent concurrent scans
        guard !state.isScanning else { return }

        state.isScanning = true
        updateMenuBarIcon()

        let result = await scanner.runFullScan()

        // Fix #5: Simplified assignments using structured results
        state.lastScanDate = result.scanDate
        state.mcpResult = result.mcp
        state.skillResult = result.skill
        state.scannerInfo = ScannerInfo(
            mcpScannerVersion: result.mcpScannerVersion,
            skillScannerVersion: result.skillScannerVersion,
            skillScannerInstalled: result.skillScannerInstalled
        )
        state.isScanning = false

        // Fix #3: Reschedule timer if config interval changed
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

    // Fix #11: Removed redundant MainActor.run since class is already @MainActor
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

        // Resize to fit content
        let width = max(24, (statusView?.fittingSize.width ?? 24) + 8)
        statusView?.frame = NSRect(x: 0, y: 0, width: width, height: 22)
        statusItem.button?.frame = statusView?.frame ?? NSRect(x: 0, y: 0, width: width, height: 22)
        statusItem.length = width
    }
}
