@preconcurrency import Dispatch
import Foundation

/// Ensures required CLI tools are available. Installs missing ones automatically on first launch.
actor DependencyManager {
    private let logFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/mcp-scan/agentguard.log")

    private func log(_ msg: String) {
        let line = "[\(Date())] [deps] \(msg)\n"
        if let data = line.data(using: .utf8),
           let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? line.write(to: logFile, atomically: true, encoding: .utf8)
        }
    }

    /// Resolve the full path of an executable by checking common locations and /usr/bin/which.
    private func resolveExecutable(_ name: String) -> String? {
        if name.hasPrefix("/") { return name }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let commonPaths = [
            "\(home)/.local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
        ]
        for path in commonPaths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // Fall back to /usr/bin/which
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

    /// Run a process with argument array (no shell interpolation). Synchronous helper for actor context.
    private func runProcessSync(_ executable: String, arguments: [String], timeout: TimeInterval = 30) -> ProcessResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return ProcessResult(output: "", success: false)
        }

        let timeoutWork = DispatchWorkItem { [weak process] in
            guard let process = process, process.isRunning else { return }
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeoutWork.cancel()
        let output = String(data: data, encoding: .utf8) ?? ""
        return ProcessResult(output: output, success: process.terminationStatus == 0)
    }

    /// Run a process asynchronously with argument array (no shell interpolation).
    private func runProcess(_ executable: String, arguments: [String], timeout: TimeInterval = 30) async -> ProcessResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return ProcessResult(output: "", success: false)
        }

        let timeoutWork = DispatchWorkItem { [weak process] in
            guard let process = process, process.isRunning else { return }
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                timeoutWork.cancel()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: ProcessResult(output: output, success: process.terminationStatus == 0))
            }
        }
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
