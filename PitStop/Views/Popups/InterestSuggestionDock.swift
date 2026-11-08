import SwiftUI

/// Compact quick-stop suggestion docked at the bottom: one line ("Smoothie shop 2 blocks ahead,
/// +0.2 mi. Stop by?") with Add stop · Save for later · ✕.
struct InterestSuggestionDock: View {
    let suggestion: InterestSuggestion
    let isSaved: Bool
    let onAddStop: () -> Void
    let onSave: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: suggestion.interest?.symbol ?? suggestion.destination.category.symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Theme.sky.gradient, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.message)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Text(suggestion.destination.name).lineLimit(1)
                        if !suggestion.destination.isPartner {
                            Text("· Not on PitStop yet")
                        }
                        if suggestion.usedAI { Image(systemName: "sparkles").foregroundStyle(Theme.sky) }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.subheadline.weight(.bold))
                }
                .frame(width: 44, height: 44)
                .background(Color.secondary.opacity(0.15), in: Circle())
                .accessibilityLabel("Dismiss suggestion")
            }
            HStack(spacing: 8) {
                Button(action: onSave) {
                    Label(isSaved ? "Saved" : "Save for later", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isSaved)
                Button(action: onAddStop) {
                    Label("Add stop", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.sky)
            }
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.sky.opacity(0.45), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
    }
}
