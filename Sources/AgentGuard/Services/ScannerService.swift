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
    private let configFile: URL
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
        configFile = home.appendingPathComponent(".config/mcp-scan/config")
        ignoreFile = cacheDir.appendingPathComponent("ignore.json")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
    }

    // MARK: - Process helpers

    /// Resolve the full path of an executable by checking common locations and using /usr/bin/which.
    private func resolveExecutable(_ name: String) async -> String? {
        // If already an absolute path, use directly
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
                Thread.sleep(forTimeInterval: 0.1)
            }
            if process.isRunning {
                process.terminate()
            }
            process.waitUntilExit()
            // Close file handle and flush to disk before reading
            try? stdout.synchronizeFile()
            try? stdout.close()
            // Small delay to ensure filesystem sync
            Thread.sleep(forTimeInterval: 0.1)
            let output = (try? String(contentsOf: tmpFile, encoding: .utf8)) ?? ""
            try? FileManager.default.removeItem(at: tmpFile)
            return output
        }.value

        return result
    }

    /// Legacy shell helper — kept private, only for safe hardcoded commands.
    private func shell(_ command: String, timeout: TimeInterval = 120) async throws -> String {
        let tmpFile = cacheDir.appendingPathComponent("shell-\(UUID().uuidString).tmp")
        let fullCommand = "\(command) > '\(tmpFile.path)' 2>/dev/null"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", fullCommand]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()

        let result: String = await Task.detached {
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }

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
        var interval = 30
        var skillDirs: [String]?

        if let content = try? String(contentsOf: configFile, encoding: .utf8) {
            for line in content.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("SCAN_INTERVAL=") {
                    let val = trimmed.replacingOccurrences(of: "SCAN_INTERVAL=", with: "")
                        .components(separatedBy: "#").first?
                        .trimmingCharacters(in: .whitespaces) ?? ""
                    interval = Int(val) ?? 30
                }
                if trimmed.hasPrefix("SKILL_DIRS=") {
                    let val = trimmed.replacingOccurrences(of: "SKILL_DIRS=", with: "")
                        .replacingOccurrences(of: "\"", with: "")
                        .components(separatedBy: "#").first?
                        .trimmingCharacters(in: .whitespaces) ?? ""
                    let expanded = val.replacingOccurrences(of: "$HOME", with: FileManager.default.homeDirectoryForCurrentUser.path)
                    skillDirs = expanded.components(separatedBy: ":").filter { !$0.isEmpty }
                }
            }
        }

        let dirs = skillDirs ?? defaultSkillDirs.map {
            $0.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
        }
        return (interval, dirs)
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
        loadConfig().interval
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

        return ScanResult(
            mcp: mcp,
            skill: skill,
            mcpScannerVersion: await mcpVer,
            skillScannerVersion: await skillVer,
            skillScannerInstalled: await hasSkillScanner,
            scanDate: Date(),
            scanInterval: config.interval
        )
    }

    private func runMCPScan(ignored: Set<String>) async -> MCPResult {
        guard let mcpPath = await resolveExecutable("mcp-scanner") else {
            return .empty
        }

        let jsonStr: String
        let raw = await runProcess(mcpPath, arguments: ["--analyzers", "yara", "--raw", "known-configs"])
        // Strip any non-JSON prefix (scanner outputs logs before JSON)
        if let idx = raw.firstIndex(of: "{") {
            jsonStr = String(raw[idx...])
        } else {
            return .empty
        }

        guard let data = jsonStr.data(using: .utf8),
              let configs = try? JSONSerialization.jsonObject(with: data) as? [String: [[String: Any]]] else {
            return .empty
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

        return MCPResult(
            findings: findings.sorted { $0.severity < $1.severity },
            safeServers: safe,
            configCount: configCount,
            serverCount: servers.count,
            toolCount: toolCount
        )
    }

    private func runSkillScan(dirs: [String], ignored: Set<String>) async -> SkillResult {
        guard let skillPath = await resolveExecutable("skill-scanner") else {
            return SkillResult(findings: [], safeSkills: [], skillCount: 0)
        }

        let existingDirs = dirs.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existingDirs.isEmpty else {
            return SkillResult(findings: [], safeSkills: [], skillCount: 0)
        }

        var allEntries: [[String: Any]] = []

        for dir in existingDirs {
            let raw = await runProcess(skillPath, arguments: ["scan-all", dir, "--recursive", "--format", "json"])
            let cleaned = raw.sanitizedForJSON()
            guard let data = cleaned.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else {
                continue
            }
            allEntries.append(contentsOf: results)
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
            skillCount: allSkills.count
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
}

struct MCPResult {
    let findings: [Finding]
    let safeServers: [SafeItem]
    let configCount: Int
    let serverCount: Int
    let toolCount: Int

    static let empty = MCPResult(findings: [], safeServers: [], configCount: 0, serverCount: 0, toolCount: 0)
}

struct SkillResult {
    let findings: [Finding]
    let safeSkills: [SafeItem]
    let skillCount: Int
}
