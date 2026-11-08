import SwiftUI

/// "Suggested for you" rows: label chip (Promotion / New / Matches your interests), the AI's personal
/// reason, and distance. Tapping one plans a run there.
struct SuggestedForYouView: View {
    @Environment(AppState.self) private var app
    /// Called after a suggestion becomes the destination (e.g. switch to the map).
    var onPlan: () -> Void = {}

    var body: some View {
        let engine = app.recommendations
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Suggested for you", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(Theme.sky)
                Spacer()
                if engine.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        app.refreshRecommendations(force: true)
                    } label: {
                        Image(systemName: "arrow.clockwise").font(.subheadline.weight(.semibold))
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Refresh suggestions")
                }
            }

            if !engine.usedAI, let error = engine.aiError, !engine.items.isEmpty {
                AIUnavailableNote(error: error)
            }

            if engine.items.isEmpty && !engine.isLoading {
                Text(app.preferences.interests.isEmpty
                     ? "Pick a few interests in Settings → AI → Interests to get suggestions."
                     : "No suggestions nearby yet. Try again after you move or add interests.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(engine.items) { item in
                Button {
                    app.planRun(to: item.destination)
                    onPlan()
                } label: {
                    RecommendationRow(item: item)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct RecommendationRow: View {
    let item: Recommendation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.destination.category.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background((item.destination.isPartner ? Theme.coral : Theme.sky).gradient,
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.destination.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Format.distance(item.distance)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Label(item.label.title, systemImage: item.label.symbol)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .foregroundStyle(item.label == .interest ? Theme.sky : Color.black.opacity(0.8))
                        .background(item.label == .interest ? AnyShapeStyle(Theme.sky.opacity(0.15)) : AnyShapeStyle(Theme.sun),
                                    in: Capsule())
                    if let reward = item.reward {
                        Text(reward).font(.caption2.weight(.semibold)).foregroundStyle(Theme.coral).lineLimit(1)
                    } else if !item.destination.isPartner {
                        Text("Not on PitStop yet").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(item.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Plans a run here")
    }
}

/// Compact sheet on the map (small detent first, so the map stays visible).
struct SuggestionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// During a run, open at the smallest size so the route stays visible.
    var compact = false
    @State private var detent: PresentationDetent = .height(260)

    var body: some View {
        ScrollView {
            SuggestedForYouView { dismiss() }
                .padding()
        }
        .presentationDetents([.height(120), .height(260), .medium, .large], selection: $detent)
        .presentationBackgroundInteraction(.enabled(upThrough: .height(260)))
        .presentationDragIndicator(.visible)
        .onAppear { detent = compact ? .height(120) : .height(260) }
    }
}
