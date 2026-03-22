import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @State private var scanInterval: Int = 30
    @State private var skillDirs: String = ""
    @State private var launchAtLogin: Bool = false
    @State private var saved = false

    private let configFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/mcp-scan/config")

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AgentGuard")
                        .font(.system(size: 16, weight: .bold))
                    Text("Security scanner for MCP servers & AI agent skills")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)

            Divider()

            // Settings form
            Form {
                Section("Scanning") {
                    Picker("Scan interval", selection: $scanInterval) {
                        Text("5 minutes").tag(5)
                        Text("10 minutes").tag(10)
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                        Text("6 hours").tag(360)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Skill directories")
                        TextEditor(text: $skillDirs)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 60)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.04)))
                        Text("One directory per line. Leave empty for defaults.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                Section("General") {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { newValue in
                            setLaunchAtLogin(newValue)
                        }
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Scanners") {
                        VStack(alignment: .trailing, spacing: 2) {
                            Link("mcp-scanner (Cisco)", destination: URL(string: "https://github.com/cisco-ai-defense/mcp-scanner")!)
                            Link("skill-scanner (Cisco)", destination: URL(string: "https://github.com/cisco-ai-defense/skill-scanner")!)
                        }
                        .font(.system(size: 11))
                    }
                    LabeledContent("Source") {
                        Link("github.com/naufalafif/agent-guard",
                             destination: URL(string: "https://github.com/naufalafif/agent-guard")!)
                            .font(.system(size: 11))
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            // Footer
            HStack {
                if saved {
                    Text("Saved")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
                Spacer()
                Button("Save") {
                    saveConfig()
                    withAnimation { saved = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { saved = false }
                    }
                }
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 420, height: 480)
        .onAppear { loadConfig() }
    }

    // MARK: - Config IO

    private func loadConfig() {
        guard let content = try? String(contentsOf: configFile, encoding: .utf8) else { return }
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("SCAN_INTERVAL=") {
                let val = trimmed.replacingOccurrences(of: "SCAN_INTERVAL=", with: "")
                    .components(separatedBy: "#").first?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                scanInterval = Int(val) ?? 30
            }
            if trimmed.hasPrefix("SKILL_DIRS=") {
                let val = trimmed.replacingOccurrences(of: "SKILL_DIRS=", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                    .components(separatedBy: "#").first?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                skillDirs = val.replacingOccurrences(of: ":", with: "\n")
            }
        }

        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func saveConfig() {
        let dir = configFile.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var lines = ["SCAN_INTERVAL=\(scanInterval)  # Scan interval in minutes"]
        let dirs = skillDirs.trimmingCharacters(in: .whitespacesAndNewlines)
        if !dirs.isEmpty {
            let joined = dirs.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: ":")
            lines.append("SKILL_DIRS=\"\(joined)\"")
        }
        try? lines.joined(separator: "\n").write(to: configFile, atomically: true, encoding: .utf8)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Silently fail — user may not have granted permission
            }
        }
    }
}
