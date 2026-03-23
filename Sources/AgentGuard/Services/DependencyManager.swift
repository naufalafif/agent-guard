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

    private func shell(_ command: String, timeout: TimeInterval = 30) async -> (output: String, success: Bool) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", command]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return ("", false)
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
                continuation.resume(returning: (output, process.terminationStatus == 0))
            }
        }
    }

    private func commandExists(_ cmd: String) async -> Bool {
        let result = await shell("command -v \(cmd)", timeout: 5)
        return result.success && !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Check and install all dependencies. Safe to call multiple times.
    func ensureDependencies() async {
        log("Starting dependency check...")

        let hasUV = await commandExists("uv")
        log("uv: \(hasUV ? "found" : "missing")")

        if !hasUV {
            if await commandExists("brew") {
                log("Installing uv via brew...")
                _ = await shell("brew install uv", timeout: 120)
            } else {
                log("Installing uv via installer...")
                _ = await shell("curl -LsSf https://astral.sh/uv/install.sh | sh", timeout: 120)
            }
        }

        let hasMCP = await commandExists("mcp-scanner")
        log("mcp-scanner: \(hasMCP ? "found" : "missing")")

        if !hasMCP {
            log("Installing mcp-scanner...")
            let result = await shell("uv tool install --python 3.13 cisco-ai-mcp-scanner 2>/dev/null", timeout: 120)
            if !result.success {
                _ = await shell("uv tool install cisco-ai-mcp-scanner", timeout: 120)
            }
        }

        let hasSkill = await commandExists("skill-scanner")
        log("skill-scanner: \(hasSkill ? "found" : "missing")")

        if !hasSkill {
            log("Installing skill-scanner...")
            let result = await shell("uv tool install --python 3.13 cisco-ai-skill-scanner 2>/dev/null", timeout: 120)
            if !result.success {
                _ = await shell("uv tool install cisco-ai-skill-scanner", timeout: 120)
            }
        }

        log("Dependency check complete")
    }
}
