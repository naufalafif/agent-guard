import SwiftUI

// MARK: - Main Popover

struct PopoverView: View {
    @ObservedObject var state: ScanState
    let onScanNow: () -> Void
    let onIgnore: (String) -> Void
    let onRestore: (String) -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()

            ScrollView {
                VStack(spacing: 2) {
                    mcpSection
                    Divider().padding(.vertical, 4).padding(.horizontal, 12)
                    skillSection
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 380)

            Divider()
            footerSection
        }
        .frame(width: 320)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 10) {
            Image(systemName: state.statusIcon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(state.statusColor)
                .opacity(state.isScanning ? 0.5 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: state.isScanning)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("AgentGuard")
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 0) {
                    if state.isScanning {
                        Text("Scanning...")
                            .foregroundStyle(.secondary)
                    } else if state.totalActiveCount > 0 {
                        Text("\(state.totalActiveCount) finding\(state.totalActiveCount == 1 ? "" : "s")")
                            .foregroundStyle(state.statusColor)
                    } else {
                        Text("All clear")
                            .foregroundStyle(.green)
                    }
                    if !state.isScanning, state.lastScanDate != nil {
                        Text(" · \(state.timeSinceLastScan)")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.system(size: 11))
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - MCP

    @State private var mcpSafeExpanded = false
    @State private var mcpMutedExpanded = false

    private var mcpSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionHeader(icon: "network", title: "MCP Servers", subtitle: mcpSubtitle)

            let active = state.mcpFindings.filter { !$0.isIgnored }
            let muted = state.mcpFindings.filter { $0.isIgnored }

            if active.isEmpty && state.mcpToolCount > 0 {
                safeStatus("No findings")
            }
            ForEach(active) { finding in
                FindingRowView(finding: finding, onIgnore: onIgnore)
            }
            if !state.mcpSafeServers.isEmpty {
                ExpandableHeader(label: "Safe", count: state.mcpSafeServers.count,
                                 icon: "checkmark.shield", color: .green, isExpanded: $mcpSafeExpanded)
                if mcpSafeExpanded {
                    safeItemsList(items: state.mcpSafeServers)
                }
            }
            if !muted.isEmpty {
                ExpandableHeader(label: "Muted", count: muted.count,
                                 icon: "bell.slash", color: .gray, isExpanded: $mcpMutedExpanded)
                if mcpMutedExpanded {
                    ForEach(muted) { finding in
                        MutedFindingRow(finding: finding, onRestore: onRestore)
                    }
                }
            }
        }
    }

    // MARK: - Skills

    @State private var skillSafeExpanded = false
    @State private var skillMutedExpanded = false

    private var skillSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionHeader(icon: "cpu", title: "AI Agent Skills", subtitle: skillSubtitle)

            let active = state.skillFindings.filter { !$0.isIgnored }
            let muted = state.skillFindings.filter { $0.isIgnored }

            if !state.skillScannerInstalled {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                    Text("Install: uv tool install cisco-ai-skill-scanner")
                }
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            } else if active.isEmpty && state.skillCount > 0 {
                safeStatus("No findings")
            }
            ForEach(active) { finding in
                FindingRowView(finding: finding, onIgnore: onIgnore)
            }
            if !state.skillSafeItems.isEmpty {
                ExpandableHeader(label: "Safe", count: state.skillSafeItems.count,
                                 icon: "checkmark.shield", color: .green, isExpanded: $skillSafeExpanded)
                if skillSafeExpanded {
                    safeItemsList(items: state.skillSafeItems)
                }
            }
            if !muted.isEmpty {
                ExpandableHeader(label: "Muted", count: muted.count,
                                 icon: "bell.slash", color: .gray, isExpanded: $skillMutedExpanded)
                if skillMutedExpanded {
                    ForEach(muted) { finding in
                        MutedFindingRow(finding: finding, onRestore: onRestore)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Button {
                onScanNow()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                    Text(state.isScanning ? "Scanning..." : "Scan Now")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 5).fill(
                    state.isScanning ? Color.clear : Color.accentColor.opacity(0.12)
                ))
            }
            .buttonStyle(.plain)
            .foregroundColor(state.isScanning ? .secondary : .accentColor)
            .disabled(state.isScanning)
            .pointerCursor()

            Spacer()

            if !state.mcpScannerVersion.isEmpty {
                Text("v\(state.mcpScannerVersion)")
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
            }

            Button { onQuit() } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help("Quit AgentGuard")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Shared

    private func sectionHeader(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
            Spacer()
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func safeStatus(_ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }

    private func safeItemsList(items: [SafeItem]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(items) { item in
                HStack(spacing: 5) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.green)
                        .frame(width: 12)
                    Text(item.name)
                        .font(.system(size: 10))
                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(.leading, 28)
        .padding(.trailing, 8)
        .padding(.bottom, 4)
    }

    private var mcpSubtitle: String {
        if state.mcpToolCount == 0 && state.mcpConfigCount == 0 { return "no configs" }
        if state.mcpToolCount == 0 { return "\(state.mcpConfigCount) configs" }
        return "\(state.mcpToolCount) tools · \(state.mcpServerCount) servers"
    }

    private var skillSubtitle: String {
        if !state.skillScannerInstalled { return "not installed" }
        if state.skillCount == 0 { return "no dirs found" }
        return "\(state.skillCount) skills"
    }
}
