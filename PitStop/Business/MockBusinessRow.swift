import SwiftUI

/// One row in the Business tab list.
struct MockBusinessRow: View {
    let business: Business

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: business.category.symbol)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(business.name).font(.body.weight(.medium))
                    if business.isMock { DemoBadge(compact: true) }
                }
                Text(business.isSlow ? "Slow now · \(business.reward)" : business.category.displayName)
                    .font(.caption)
                    .foregroundStyle(business.isSlow ? Color.accentColor : .secondary)
                    .lineLimit(1)
            }
            Spacer()
            if business.isSlow {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.variableColor.iterative)
            }
        }
    }
}
