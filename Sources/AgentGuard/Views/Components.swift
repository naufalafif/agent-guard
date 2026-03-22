import SwiftUI

// MARK: - Not installed banner with install button

struct NotInstalledBanner: View {
    let name: String
    let command: String
    @State private var isInstalling = false
    @State private var installed = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if installed {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("\(name) installed — restart to activate")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            } else if isInstalling {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Installing \(name)...")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text("\(name) not installed")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        install()
                    } label: {
                        Text("Install")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .pointerCursor()
                }
                if failed {
                    Text("Install failed. Run manually: \(command)")
                        .font(.system(size: 9))
                        .foregroundStyle(.red.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func install() {
        isInstalling = true
        failed = false
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-lc", self.command]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            let success: Bool
            do {
                try process.run()
                process.waitUntilExit()
                success = process.terminationStatus == 0
            } catch {
                success = false
            }
            await MainActor.run {
                isInstalling = false
                if success {
                    installed = true
                } else {
                    failed = true
                }
            }
        }
    }
}

// MARK: - Expandable section header — full row clickable

struct ExpandableHeader: View {
    let label: String
    let count: Int
    let icon: String
    let color: Color
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(color)
                Text("\(label) (\(count))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.001)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }
}

// MARK: - Finding row — click to expand, explicit ignore button

struct FindingRowView: View {
    let finding: Finding
    let onIgnore: (String) -> Void
    @State private var isExpanded = false
    @State private var showConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row — tap to expand
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)
                    SeverityBadge(severity: finding.severity)
                    Text(finding.name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerCursor()

            // Expanded detail
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    // Full name (unwrapped)
                    Text(finding.name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)

                    ForEach(finding.details, id: \.self) { detail in
                        Text(detail)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    // Ignore action — explicit button with confirmation
                    if !showConfirm {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showConfirm = true
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "bell.slash")
                                    .font(.system(size: 9))
                                Text("Mute this finding")
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 3)
                            .padding(.horizontal, 6)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.04)))
                        }
                        .buttonStyle(.plain)
                        .pointerCursor()
                    } else {
                        HStack(spacing: 8) {
                            Text("Mute this finding?")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Cancel") {
                                withAnimation { showConfirm = false }
                            }
                            .font(.system(size: 10))
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .pointerCursor()

                            Button("Mute") {
                                onIgnore(finding.key)
                                showConfirm = false
                            }
                            .font(.system(size: 10, weight: .medium))
                            .buttonStyle(.plain)
                            .foregroundStyle(.orange)
                            .pointerCursor()
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.orange.opacity(0.06)))
                    }
                }
                .padding(.leading, 24)
                .padding(.trailing, 8)
                .padding(.bottom, 6)
            }
        }
        .background(RoundedRectangle(cornerRadius: 5).fill(isExpanded ? Color.primary.opacity(0.03) : .clear))
    }
}

// MARK: - Muted/ignored finding row — click to restore

struct MutedFindingRow: View {
    let finding: Finding
    let onRestore: (String) -> Void
    @State private var showConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showConfirm.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    SeverityBadge(severity: finding.severity, dimmed: true)
                    Text(finding.name)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerCursor()

            if showConfirm {
                HStack(spacing: 8) {
                    Text("Unmute?")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") {
                        withAnimation { showConfirm = false }
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .pointerCursor()

                    Button("Unmute") {
                        onRestore(finding.key)
                        showConfirm = false
                    }
                    .font(.system(size: 10, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .pointerCursor()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.blue.opacity(0.06)))
            }
        }
    }
}
