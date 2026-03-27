import Foundation

/// Ensures required CLI tools are available. Installs missing ones automatically on first launch.
actor DependencyManager {
    private let cacheDir: URL
    private let logFile: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        cacheDir = home.appendingPathComponent(".cache/mcp-scan")
        logFile = cacheDir.appendingPathComponent("agentguard.log")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        // Enforce on existing dir too
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: cacheDir.path)
    }

    private func log(_ msg: String) {
        let line = "[\(Date())] [deps] \(msg)\n"
        if let data = line.data(using: .utf8),
           let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? line.write(to: logFile, atomically: true, encoding: .utf8)
        }
    }

    /// Resolve the full path of an executable by checking common locations, then /usr/bin/which.
    private func resolveExecutable(_ name: String) -> String? {
        if let path = ConfigIO.findExecutable(name) { return path }
        // Fall back to /usr/bin/which using temp file (no Pipe — avoids deadlock in .app bundles)
        let result = runProcessSync("/usr/bin/which", arguments: [name], timeout: 5)
        let trimmed = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && FileManager.default.isExecutableFile(atPath: trimmed) {
            return trimmed
        }
        return nil
    }

    private struct ProcessResult {
        let output: String
        let success: Bool
    }

    /// Run a process with argument array (no shell interpolation).
    /// Uses temp file for stdout to avoid Pipe deadlocks in .app bundles.
    private func runProcessSync(
        _ executable: String, arguments: [String], timeout: TimeInterval = 30
    ) -> ProcessResult {
        let tmpFile = cacheDir.appendingPathComponent("proc-\(UUID().uuidString).tmp")
        FileManager.default.createFile(atPath: tmpFile.path, contents: nil)

        guard let stdout = FileHandle(forWritingAtPath: tmpFile.path) else {
            try? FileManager.default.removeItem(at: tmpFile)
            return ProcessResult(output: "", success: false)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stdout

        do {
            try process.run()
        } catch {
            try? stdout.close()
            try? FileManager.default.removeItem(at: tmpFile)
            return ProcessResult(output: "", success: false)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        try? stdout.synchronize()
        try? stdout.close()

        let output = (try? String(contentsOf: tmpFile, encoding: .utf8)) ?? ""
        try? FileManager.default.removeItem(at: tmpFile)
        return ProcessResult(output: output, success: process.terminationStatus == 0)
    }

    /// Run a process asynchronously with argument array (no shell interpolation).
    /// Uses temp file for stdout to avoid Pipe deadlocks in .app bundles.
    private func runProcess(
        _ executable: String, arguments: [String], timeout: TimeInterval = 30
    ) async -> ProcessResult {
        let tmpFile = cacheDir.appendingPathComponent("proc-\(UUID().uuidString).tmp")
        FileManager.default.createFile(atPath: tmpFile.path, contents: nil)

        guard let stdout = FileHandle(forWritingAtPath: tmpFile.path) else {
            try? FileManager.default.removeItem(at: tmpFile)
            return ProcessResult(output: "", success: false)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stdout

        do {
            try process.run()
        } catch {
            try? stdout.close()
            try? FileManager.default.removeItem(at: tmpFile)
            return ProcessResult(output: "", success: false)
        }

        let result: ProcessResult = await Task.detached {
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if process.isRunning {
                process.terminate()
            }
            process.waitUntilExit()

            try? stdout.synchronize()
            try? stdout.close()
            try? await Task.sleep(nanoseconds: 100_000_000)

            let output = (try? String(contentsOf: tmpFile, encoding: .utf8)) ?? ""
            try? FileManager.default.removeItem(at: tmpFile)
            return ProcessResult(output: output, success: process.terminationStatus == 0)
        }.value

        return result
    }

    private func commandExists(_ name: String) -> Bool {
        resolveExecutable(name) != nil
    }

    /// Check and install all dependencies. Safe to call multiple times.
    func ensureDependencies() async {
        log("Starting dependency check...")

        let hasUV = commandExists("uv")
        log("uv: \(hasUV ? "found" : "missing")")

        if !hasUV {
            if let brewPath = resolveExecutable("brew") {
                log("Installing uv via brew...")
                _ = await runProcess(brewPath, arguments: ["install", "uv"], timeout: 120)
            } else {
                log("WARNING: uv not found and brew not available. "
                    + "Please install uv manually: "
                    + "https://docs.astral.sh/uv/getting-started/installation/")
            }
        }

        guard let uvPath = resolveExecutable("uv") else {
            log("uv still not available after install attempt. Skipping scanner installation.")
            log("Dependency check complete (scanners will show as not active)")
            return
        }

        let hasMCP = commandExists("mcp-scanner")
        log("mcp-scanner: \(hasMCP ? "found" : "missing")")

        if !hasMCP {
            log("Installing mcp-scanner...")
            let mcpArgs = ["tool", "install", "--python", "3.13", "cisco-ai-mcp-scanner"]
            let result = await runProcess(uvPath, arguments: mcpArgs, timeout: 120)
            if !result.success {
                _ = await runProcess(uvPath, arguments: ["tool", "install", "cisco-ai-mcp-scanner"], timeout: 120)
            }
        }

        let hasSkill = commandExists("skill-scanner")
        log("skill-scanner: \(hasSkill ? "found" : "missing")")

        if !hasSkill {
            log("Installing skill-scanner...")
            let skillArgs = ["tool", "install", "--python", "3.13", "cisco-ai-skill-scanner"]
            let result = await runProcess(uvPath, arguments: skillArgs, timeout: 120)
            if !result.success {
                _ = await runProcess(uvPath, arguments: ["tool", "install", "cisco-ai-skill-scanner"], timeout: 120)
            }
        }

        log("Dependency check complete")
    }
}
