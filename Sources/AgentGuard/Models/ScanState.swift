import Foundation
import SwiftUI

@MainActor
final class ScanState: ObservableObject {
    @Published var isScanning = false
    @Published var lastScanDate: Date?
    @Published var mcpResult: MCPResult?
    @Published var skillResult: SkillResult?
    @Published var scannerInfo: ScannerInfo?

    // MARK: - Computed accessors (preserve existing API)

    var mcpFindings: [Finding] {
        get { mcpResult?.findings ?? [] }
        set {
            var r = mcpResult ?? .empty
            r = MCPResult(findings: newValue, safeServers: r.safeServers,
                          configCount: r.configCount, serverCount: r.serverCount, toolCount: r.toolCount)
            mcpResult = r
        }
    }

    var skillFindings: [Finding] {
        get { skillResult?.findings ?? [] }
        set {
            let r = skillResult ?? SkillResult(findings: [], safeSkills: [], skillCount: 0)
            skillResult = SkillResult(findings: newValue, safeSkills: r.safeSkills, skillCount: r.skillCount)
        }
    }

    var mcpSafeServers: [SafeItem] { mcpResult?.safeServers ?? [] }
    var mcpConfigCount: Int { mcpResult?.configCount ?? 0 }
    var mcpServerCount: Int { mcpResult?.serverCount ?? 0 }
    var mcpToolCount: Int { mcpResult?.toolCount ?? 0 }

    var skillSafeItems: [SafeItem] { skillResult?.safeSkills ?? [] }
    var skillCount: Int { skillResult?.skillCount ?? 0 }

    var skillScannerInstalled: Bool { scannerInfo?.skillScannerInstalled ?? false }
    var mcpScannerVersion: String { scannerInfo?.mcpScannerVersion ?? "" }
    var skillScannerVersion: String { scannerInfo?.skillScannerVersion ?? "" }

    // MARK: - Derived

    var activeFindings: [Finding] {
        (mcpFindings + skillFindings).filter { !$0.isIgnored }
    }

    var ignoredFindings: [Finding] {
        (mcpFindings + skillFindings).filter { $0.isIgnored }
    }

    var highCount: Int {
        activeFindings.filter { $0.severity == .critical || $0.severity == .high }.count
    }

    var medCount: Int {
        activeFindings.filter { $0.severity == .medium }.count
    }

    var lowCount: Int {
        activeFindings.filter { $0.severity == .low }.count
    }

    var totalActiveCount: Int { activeFindings.count }

    var statusColor: Color {
        if highCount > 0 { return Color(hex: "#FF4444") }
        if medCount > 0 { return Color(hex: "#FFAA00") }
        if lowCount > 0 { return Color(hex: "#88AA00") }
        return Color(hex: "#44BB44")
    }

    var statusIcon: String {
        if isScanning { return "shield.lefthalf.filled" }
        if totalActiveCount > 0 { return "exclamationmark.shield.fill" }
        return "checkmark.shield.fill"
    }

    var timeSinceLastScan: String {
        guard let date = lastScanDate else { return "never" }
        let minutes = Int(-date.timeIntervalSinceNow / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return "\(hours)h ago"
    }
}

// MARK: - Scanner info

struct ScannerInfo {
    let mcpScannerVersion: String
    let skillScannerVersion: String
    let skillScannerInstalled: Bool
}
