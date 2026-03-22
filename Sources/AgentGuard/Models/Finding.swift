import Foundation

enum Severity: String, Codable, Comparable {
    case critical = "CRITICAL"
    case high = "HIGH"
    case medium = "MEDIUM"
    case low = "LOW"
    case info = "INFO"
    case unknown = "UNKNOWN"

    var order: Int {
        switch self {
        case .critical: 0
        case .high: 1
        case .medium: 2
        case .low: 3
        case .info: 4
        case .unknown: 5
        }
    }

    var color: String {
        switch self {
        case .critical, .high: "#FF4444"
        case .medium: "#FFAA00"
        case .low: "#88AA00"
        case .info, .unknown: "#888888"
        }
    }

    static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.order < rhs.order
    }
}

struct Finding: Identifiable {
    let id = UUID()
    let key: String          // ignore key
    let name: String         // "server/tool" or "skill — title"
    let severity: Severity
    let details: [String]    // threat names, category, rule, etc.
    var isIgnored: Bool
}

struct SafeItem: Identifiable {
    let id = UUID()
    let name: String
    let detail: String       // "3 tools" or empty
}
