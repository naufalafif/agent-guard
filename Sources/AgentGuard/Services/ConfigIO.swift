import Foundation

/// Shared config file I/O used by both ScannerService and SettingsView.
enum ConfigIO {
    static let configFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/mcp-scan/config")

    struct Config {
        var interval: Int = 30
        var skillDirs: String = ""  // colon-separated, unexpanded
    }

    /// Read config from disk. Returns defaults if file doesn't exist.
    static func load() -> Config {
        var config = Config()
        guard let content = try? String(contentsOf: configFile, encoding: .utf8) else {
            return config
        }
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("SCAN_INTERVAL=") {
                let val = trimmed.replacingOccurrences(of: "SCAN_INTERVAL=", with: "")
                    .components(separatedBy: "#").first?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                config.interval = Int(val) ?? 30
            }
            if trimmed.hasPrefix("SKILL_DIRS=") {
                let val = trimmed.replacingOccurrences(of: "SKILL_DIRS=", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                    .components(separatedBy: "#").first?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                config.skillDirs = val
            }
        }
        return config
    }

    /// Write config to disk with hardened permissions.
    static func save(_ config: Config) {
        let dir = configFile.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var lines = ["SCAN_INTERVAL=\(config.interval)  # Scan interval in minutes"]
        let dirs = config.skillDirs.trimmingCharacters(in: .whitespacesAndNewlines)
        if !dirs.isEmpty {
            lines.append("SKILL_DIRS=\"\(dirs)\"")
        }
        try? lines.joined(separator: "\n").write(to: configFile, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: configFile.path)
    }

    /// Resolve an executable by checking common paths. Returns nil if not found locally.
    /// Does NOT fall back to `which` — callers can add that themselves.
    static func findExecutable(_ name: String) -> String? {
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
        return nil
    }
}
