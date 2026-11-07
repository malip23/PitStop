import SwiftUI

/// Small "DEMO" capsule marking mock businesses, so judges know they're test data.
struct DemoBadge: View {
    var compact = false

    var body: some View {
        Text("DEMO")
            .font(.system(size: compact ? 8 : 10, weight: .heavy, design: .rounded))
            .tracking(0.5)
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 4 : 6)
            .padding(.vertical, compact ? 1.5 : 2.5)
            .background(Color.indigo, in: Capsule())
            .overlay(Capsule().stroke(.white, lineWidth: compact ? 1 : 0))
            .accessibilityLabel("Demo business")
    }
}
