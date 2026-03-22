import SwiftUI

struct SeverityBadge: View {
    let severity: Severity
    var dimmed: Bool = false

    var body: some View {
        Text(severity.rawValue)
            .font(.system(size: 8, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: severity.color).opacity(dimmed ? 0.1 : 0.2))
            )
            .foregroundStyle(Color(hex: severity.color).opacity(dimmed ? 0.4 : 1.0))
    }
}
