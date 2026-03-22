import Foundation

/// Ensures required CLI tools are available. Installs missing ones automatically on first launch.
actor DependencyManager {
    private func shell(_ command: String) async -> (output: String, success: Bool) {
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

        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: (output, process.terminationStatus == 0))
            }
        }
    }

    private func commandExists(_ cmd: String) async -> Bool {
        let result = await shell("command -v \(cmd)")
        return result.success && !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Check and install all dependencies. Safe to call multiple times.
    func ensureDependencies() async {
        // 1. Ensure uv is available (needed to install scanners)
        if !(await commandExists("uv")) {
            // Try Homebrew first
            if await commandExists("brew") {
                _ = await shell("brew install uv")
            } else {
                // Fallback: official uv installer
                _ = await shell("curl -LsSf https://astral.sh/uv/install.sh | sh")
            }
        }

        // 2. Ensure mcp-scanner
        if !(await commandExists("mcp-scanner")) {
            // Try with Python 3.13 first, fall back to default
            let result = await shell("uv tool install --python 3.13 cisco-ai-mcp-scanner 2>/dev/null")
            if !result.success {
                _ = await shell("uv tool install cisco-ai-mcp-scanner")
            }
        }

        // 3. Ensure skill-scanner
        if !(await commandExists("skill-scanner")) {
            let result = await shell("uv tool install --python 3.13 cisco-ai-skill-scanner 2>/dev/null")
            if !result.success {
                _ = await shell("uv tool install cisco-ai-skill-scanner")
            }
        }
    }
}
