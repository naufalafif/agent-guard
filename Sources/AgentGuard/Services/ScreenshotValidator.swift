import Cocoa

/// Takes a screenshot of a specific window for automated UI validation.
/// Usage: ScreenshotValidator.capture(window:) saves a timestamped PNG.
enum ScreenshotValidator {
    private static let outputDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/mcp-scan/screenshots")

    /// Capture a screenshot of the given window and save to disk.
    @MainActor
    static func capture(window: NSWindow?, label: String = "popover") -> URL? {
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
        // Enforce on existing dir too
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: outputDir.path)

        guard let window = window,
              let screen = window.screen else { return nil }

        // Get the window's frame in screen coordinates
        let windowFrame = window.frame

        // Convert to CGWindow coordinates (screen coordinates with origin at top-left)
        let screenFrame = screen.frame
        let cgRect = CGRect(
            x: windowFrame.origin.x,
            y: screenFrame.height - windowFrame.origin.y - windowFrame.height,
            width: windowFrame.width,
            height: windowFrame.height
        )

        guard let cgImage = CGWindowListCreateImage(
            cgRect,
            .optionIncludingWindow,
            CGWindowID(window.windowNumber),
            [.boundsIgnoreFraming]
        ) else { return nil }

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else { return nil }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let fileName = "\(label)-\(timestamp).png"
        let fileURL = outputDir.appendingPathComponent(fileName)

        do {
            try pngData.write(to: fileURL)
            return fileURL
        } catch {
            return nil
        }
    }

    /// Capture the popover content from an NSPopover.
    @MainActor
    static func capturePopover(_ popover: NSPopover, label: String = "popover") -> URL? {
        guard popover.isShown,
              let contentWindow = popover.contentViewController?.view.window else { return nil }
        return capture(window: contentWindow, label: label)
    }
}
