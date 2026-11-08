import SwiftUI

/// Small inline note shown wherever an AI feature fell back to its non-AI version.
/// Tap it to see the exact reason (useful when setting up, or for judges asking "what happened?").
struct AIUnavailableNote: View {
    let error: AIError?
    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(summary, systemImage: "sparkles.slash")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.12), in: Capsule())
            if showDetail, let detail = error?.localizedDescription {
                Text(detail)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy) { showDetail.toggle() } }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double-tap for details")
    }

    /// The AI answered but its pick failed our checks, which is different from AI being unavailable.
    private var summary: String {
        switch error {
        case .badJSON?: "AI's pick didn't pass our checks, using standard picks"
        case .tooManyToolCalls?: "AI took too many steps, using standard picks"
        default: error?.shortNote ?? "AI unavailable, using standard picks"
        }
    }
}
