import SwiftUI

/// Small inline note shown wherever an AI feature fell back to its non-AI version.
struct AIUnavailableNote: View {
    let error: AIError?

    var body: some View {
        Label(error?.shortNote ?? "AI unavailable, using standard picks", systemImage: "sparkles.slash")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .accessibilityLabel("AI unavailable")
    }
}
