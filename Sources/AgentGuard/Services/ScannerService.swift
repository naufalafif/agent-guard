@preconcurrency import Dispatch
import Foundation

// MARK: - String extension for JSON sanitization

extension String {
    /// Replace control characters (except newline) with spaces for safe JSON parsing.
    func sanitizedForJSON() -> String {
        unicodeScalars.map { ($0.value < 0x20 && $0.value != 0x0A) || $0.value == 0x7F ? " " : String($0) }.joined()
    }
}

actor ScannerService {
    private let cacheDir: URL
    private let ignoreFile: URL

    private let defaultSkillDirs: [String] = [
        "~/.cursor/skills", "~/.cursor/rules",
        "~/.claude/skills", "~/.claude/plugins",
        "~/.agents/skills", "~/.codex/skills", "~/.cline/skills",
        "~/.opencode/skills", "~/.config/opencode", "~/.continue/skills",
        "~/.gemini/skills", "~/.codeium/windsurf/skills", "~/.kiro/skills",
        "~/.aider", "~/.gpt-engineer",
    ]

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        cacheDir = home.appendingPathComponent(".cache/mcp-scan")
        ignoreFile = cacheDir.appendingPathComponent("ignore.json")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        // Enforce permissions on existing dirs (may have been created with defaults)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: cacheDir.path)
        let screenshotDir = cacheDir.appendingPathComponent("screenshots")
        if FileManager.default.fileExists(atPath: screenshotDir.path) {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: screenshotDir.path)
        }
    }

    // MARK: - Process helpers

    /// Resolve the full path of an executable by checking common locations, then /usr/bin/which.
    private func resolveExecutable(_ name: String) async -> String? {
        if let path = ConfigIO.findExecutable(name) { return path }
        // Fall back to /usr/bin/which
        let result = await runProcess("/usr/bin/which", arguments: [name], timeout: 5)
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && FileManager.default.isExecutableFile(atPath: trimmed) {
            return trimmed
        }
        return nil
    }

    /// Run a process with an argument array (no shell interpolation) and return stdout.
    private func runProcess(_ executable: String, arguments: [String], timeout: TimeInterval = 120) async -> String {
        let tmpFile = cacheDir.appendingPathComponent("proc-\(UUID().uuidString).tmp")

        guard let stdout = FileHandle(forWritingAtPath: tmpFile.path) ?? {
            FileManager.default.createFile(atPath: tmpFile.path, contents: nil)
            return FileHandle(forWritingAtPath: tmpFile.path)
        }() else {
            return ""
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            try? stdout.close()
            try? FileManager.default.removeItem(at: tmpFile)
            return ""
        }

        let result: String = await Task.detached {
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if process.isRunning {
                process.terminate()
            }
            process.waitUntilExit()
            // Flush and close file handle before reading
            try? stdout.synchronize()
            try? stdout.close()
            // Small delay to ensure filesystem sync
            try? await Task.sleep(nanoseconds: 100_000_000)
            let output = (try? String(contentsOf: tmpFile, encoding: .utf8)) ?? ""
            try? FileManager.default.removeItem(at: tmpFile)
            return output
        }.value

        return result
    }

    private func commandExists(_ cmd: String) async -> Bool {
        let resolved = await resolveExecutable(cmd)
        return resolved != nil
    }

    private func getVersion(_ cmd: String) async -> String {
        guard let path = await resolveExecutable(cmd) else { return "" }
        // Try --version, then -V
        for flag in ["--version", "-V"] {
            let out = await runProcess(path, arguments: [flag], timeout: 10)
            if let match = out.range(of: #"[0-9]+\.[0-9]+\.[0-9]+"#, options: .regularExpression) {
                return String(out[match])
            }
        }
        // Fall back to uv tool list
        if let uvPath = await resolveExecutable("uv") {
            let out = await runProcess(uvPath, arguments: ["tool", "list"], timeout: 10)
            for line in out.components(separatedBy: "\n") {
                if line.localizedCaseInsensitiveContains(cmd),
                   let match = line.range(of: #"[0-9]+\.[0-9]+\.[0-9]+"#, options: .regularExpression) {
                    return String(line[match])
                }
            }
        }
        return ""
    }

    // MARK: - Config

    private func loadConfig() -> (interval: Int, skillDirs: [String]) {
        let raw = ConfigIO.load()
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        var skillDirs: [String]?
        if !raw.skillDirs.isEmpty {
            let expanded = raw.skillDirs
                .replacingOccurrences(of: "$HOME", with: home)
                .replacingOccurrences(of: "~", with: home)
            skillDirs = expanded.components(separatedBy: ":").filter { !$0.isEmpty }
        }

        let configured = skillDirs ?? defaultSkillDirs.map {
            $0.replacingOccurrences(of: "~", with: home)
        }

        // Always include active Claude plugin install paths on top of configured dirs.
        let claudeDirs = installedClaudePluginDirs()
        let merged = (configured + claudeDirs).reduce(into: [String]()) { result, dir in
            if !result.contains(dir) { result.append(dir) }
        }
        return (raw.interval, merged)
    }

    /// Derive a friendly display name from a config file path.
    private func friendlyConfigName(_ path: String) -> String {
        let lower = path.lowercased()
        if lower.contains("claude") { return "Claude" }
        if lower.contains("cursor") { return "Cursor" }
        if lower.contains("windsurf") { return "Windsurf" }
        if lower.contains("vscode") || lower.contains("code") { return "VS Code" }
        if lower.contains("zed") { return "Zed" }
        if lower.contains("cline") { return "Cline" }
        if lower.contains("continue") { return "Continue" }
        if lower.contains("opencode") { return "OpenCode" }
        let filename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        return filename
    }

    /// Read ~/.claude/plugins/installed_plugins.json and return one installPath per plugin.
    /// Prefers user-scoped installs over project-scoped to avoid scanning the same plugin twice.
    private func installedClaudePluginDirs() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let manifestURL = URL(fileURLWithPath: "\(home)/.claude/plugins/installed_plugins.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plugins = json["plugins"] as? [String: [[String: Any]]] else {
            return []
        }
        var dirs: [String] = []
        for entries in plugins.values {
            // Prefer user-scoped entry; fall back to first available.
            let preferred = entries.first(where: { ($0["scope"] as? String) == "user" }) ?? entries.first
            if let path = preferred?["installPath"] as? String, !path.isEmpty {
                dirs.append(path)
            }
        }
        return dirs
    }

    // MARK: - Ignore list

    func loadIgnoreList() -> Set<String> {
        guard let data = try? Data(contentsOf: ignoreFile),
              let list = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(list)
    }

    func addIgnore(_ key: String) {
        var list = Array(loadIgnoreList())
        if !list.contains(key) {
            list.append(key)
        }
        atomicWriteIgnoreList(list)
    }

    func removeIgnore(_ key: String) {
        var list = Array(loadIgnoreList())
        list.removeAll { $0 == key }
        atomicWriteIgnoreList(list)
    }

    /// Write the ignore list to a temp file and rename for atomicity.
    private func atomicWriteIgnoreList(_ list: [String]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        let tmp = ignoreFile.appendingPathExtension("tmp")
        do {
            try data.write(to: tmp)
            _ = try FileManager.default.replaceItemAt(ignoreFile, withItemAt: tmp)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ignoreFile.path)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    /// Public method to read the configured scan interval (in minutes).
    func loadScanInterval() -> Int {
        ConfigIO.load().interval
    }

    // MARK: - Run scans

    func runFullScan() async -> ScanResult {
        let config = loadConfig()
        let ignored = loadIgnoreList()

        async let mcpResult = runMCPScan(ignored: ignored)
        async let skillResult = runSkillScan(dirs: config.skillDirs, ignored: ignored)
        async let mcpVer = getVersion("mcp-scanner")
        async let skillVer = getVersion("skill-scanner")
        async let hasSkillScanner = commandExists("skill-scanner")

        let mcp = await mcpResult
        let skill = await skillResult

        var errors: [String] = []
        if let err = mcp.error { errors.append(err) }
        if let err = skill.error { errors.append(err) }

        return ScanResult(
            mcp: mcp,
            skill: skill,
            mcpScannerVersion: await mcpVer,
            skillScannerVersion: await skillVer,
            skillScannerInstalled: await hasSkillScanner,
            scanDate: Date(),
            scanInterval: config.interval,
            errors: errors
        )
    }

    private func runMCPScan(ignored: Set<String>) async -> MCPResult {
        guard let mcpPath = await resolveExecutable("mcp-scanner") else {
            return MCPResult(findings: [], safeServers: [], configInfos: [], configCount: 0, serverCount: 0, toolCount: 0,
                             error: "mcp-scanner not found")
        }

        let jsonStr: String
        let raw = await runProcess(mcpPath, arguments: ["--analyzers", "yara", "--raw", "known-configs"])
        // Strip any non-JSON prefix (scanner outputs logs before JSON)
        if let idx = raw.firstIndex(of: "{") {
            jsonStr = String(raw[idx...])
        } else {
            let hint = raw.isEmpty ? "no output" : "unexpected output"
            return MCPResult(findings: [], safeServers: [], configInfos: [], configCount: 0, serverCount: 0, toolCount: 0,
                             error: "mcp-scanner failed (\(hint))")
        }

        guard let data = jsonStr.data(using: .utf8),
              let configs = try? JSONSerialization.jsonObject(with: data) as? [String: [[String: Any]]] else {
            return MCPResult(findings: [], safeServers: [], configInfos: [], configCount: 0, serverCount: 0, toolCount: 0,
                             error: "Failed to parse mcp-scanner output")
        }

        var findings: [Finding] = []
        var safeServers: [String: Int] = [:]
        var servers = Set<String>()
        var toolCount = 0
        var configCount = 0

        for (_, tools) in configs {
            configCount += 1
            for tool in tools {
                toolCount += 1
                let server = tool["server_name"] as? String ?? "unknown"
                servers.insert(server)
                let isSafe = tool["is_safe"] as? Bool ?? true

                if isSafe {
                    safeServers[server, default: 0] += 1
                } else {
                    let toolName = tool["tool_name"] as? String ?? "unknown"
                    let key = "\(server):\(toolName)"
                    var severity = Severity.unknown
                    var threats: [String] = []

                    if let findingsDict = tool["findings"] as? [String: [String: Any]] {
                        for (_, result) in findingsDict {
                            if let sev = result["severity"] as? String,
                               let parsed = Severity(rawValue: sev), parsed < severity {
                                severity = parsed
                            }
                            if let names = result["threat_names"] as? [String] {
                                threats.append(contentsOf: names)
                            }
                        }
                    }

                    var details = threats
                    if let desc = tool["tool_description"] as? String, !desc.isEmpty {
                        details.append(desc)
                    }

                    findings.append(Finding(
                        key: key,
                        name: "\(server) / \(toolName)",
                        severity: severity,
                        details: details,
                        isIgnored: ignored.contains(key)
                    ))
                }
            }
        }

        let safe = safeServers.sorted(by: { $0.key < $1.key }).map {
            SafeItem(name: $0.key, detail: "\($0.value) tools")
        }

        // Read each config file to extract server names for the configs section.
        let configInfos: [SafeItem] = configs.keys.sorted().compactMap { path in
            let url = URL(fileURLWithPath: path)
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let mcpServers = json["mcpServers"] as? [String: Any] else {
                return SafeItem(name: friendlyConfigName(path), detail: "")
            }
            let serverList = mcpServers.keys.sorted().joined(separator: ", ")
            return SafeItem(name: friendlyConfigName(path), detail: serverList)
        }

        return MCPResult(
            findings: findings.sorted { $0.severity < $1.severity },
            safeServers: safe,
            configInfos: configInfos,
            configCount: configCount,
            serverCount: servers.count,
            toolCount: toolCount,
            error: nil
        )
    }

    private func runSkillScan(dirs: [String], ignored: Set<String>) async -> SkillResult {
        guard let skillPath = await resolveExecutable("skill-scanner") else {
            // Not an error — skill-scanner is optional
            return SkillResult(findings: [], safeSkills: [], skillCount: 0, error: nil)
        }

        let existingDirs = dirs.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existingDirs.isEmpty else {
            return SkillResult(findings: [], safeSkills: [], skillCount: 0, error: nil)
        }

        // Scan all directories concurrently instead of sequentially.
        let allEntries: [[String: Any]] = await withTaskGroup(of: [[String: Any]].self) { group in
            for dir in existingDirs {
                group.addTask {
                    let raw = await self.runProcess(
                        skillPath, arguments: ["scan-all", dir, "--recursive", "--format", "json"])
                    let cleaned = raw.sanitizedForJSON()
                    guard let data = cleaned.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let results = json["results"] as? [[String: Any]] else {
                        return []
                    }
                    return results
                }
            }
            var combined: [[String: Any]] = []
            for await entries in group { combined.append(contentsOf: entries) }
            return combined
        }

        var findings: [Finding] = []
        var safeSkills = Set<String>()
        var allSkills = Set<String>()

        for entry in allEntries {
            let skillName = entry["skill_name"] as? String ?? "unknown"
            allSkills.insert(skillName)
            let findingsData = entry["findings"] as? [[String: Any]] ?? []

            let actionable = findingsData.filter {
                ($0["severity"] as? String ?? "").uppercased() != "INFO"
            }

            if actionable.isEmpty {
                safeSkills.insert(skillName)
            }

            for finding in findingsData {
                let sev = (finding["severity"] as? String ?? "UNKNOWN").uppercased()
                guard sev != "INFO" else { continue }

                let ruleId = finding["rule_id"] as? String ?? "UNKNOWN"
                let title = finding["title"] as? String ?? ruleId
                let category = finding["category"] as? String ?? ""
                let key = "skill:\(skillName):\(ruleId)"

                var details: [String] = []
                if !category.isEmpty { details.append("Category: \(category)") }
                details.append("Rule: \(ruleId)")

                findings.append(Finding(
                    key: key,
                    name: "\(skillName) — \(title)",
                    severity: Severity(rawValue: sev) ?? .unknown,
                    details: details,
                    isIgnored: ignored.contains(key)
                ))
            }
        }

        let safe = safeSkills.sorted().map { SafeItem(name: $0, detail: "") }

        return SkillResult(
            findings: findings.sorted { $0.severity < $1.severity },
            safeSkills: safe,
            skillCount: allSkills.count,
            error: nil
        )
    }
}

// MARK: - Result types

struct ScanResult {
    let mcp: MCPResult
    let skill: SkillResult
    let mcpScannerVersion: String
    let skillScannerVersion: String
    let skillScannerInstalled: Bool
    let scanDate: Date
    let scanInterval: Int  // minutes, from config
    let errors: [String]   // non-fatal errors to display in UI
}

struct MCPResult {
    let findings: [Finding]
    let safeServers: [SafeItem]
    let configInfos: [SafeItem]
    let configCount: Int
    let serverCount: Int
    let toolCount: Int
    let error: String?

    static let empty = MCPResult(findings: [], safeServers: [], configInfos: [],
                                 configCount: 0, serverCount: 0, toolCount: 0, error: nil)
}

struct SkillResult {
    let findings: [Finding]
    let safeSkills: [SafeItem]
    let skillCount: Int
    let error: String?
}
