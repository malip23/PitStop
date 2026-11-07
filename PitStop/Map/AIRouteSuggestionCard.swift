import SwiftUI

/// The route agent's pick: title, real distance/time/fit, the AI's reason, highlights, and
/// "Use this route" (starts navigation) / "Show other options".
struct AIRouteSuggestionCard: View {
    @Environment(AppState.self) private var app
    let suggestion: RouteAgent.Suggestion

    var body: some View {
        let option = suggestion.option
        let plan = app.planForRouting
        let target = app.targetDistance(for: plan)
        let seconds = option.distance * app.planStore.pace(for: plan.activity).secondsPerMeter

        MaterialCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("AI SUGGESTED", systemImage: "sparkles")
                            .font(.caption2.weight(.heavy))
                            .tracking(0.6)
                            .foregroundStyle(Theme.sky)
                        Text(suggestion.title).font(.title3.weight(.bold))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Format.distance(option.distance)).font(.headline.monospacedDigit())
                        Text("\(Format.minutes(seconds)) · \(Int((option.fit(target: target) * 100).rounded()))% fit")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }

                Text(suggestion.reason)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)

                if !suggestion.highlights.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(suggestion.highlights, id: \.self) { highlight in
                                Label(highlight, systemImage: "star.fill")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Theme.sky.opacity(0.15), in: Capsule())
                                    .foregroundStyle(Theme.sky)
                            }
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button("Show other options") {
                        app.showAISuggestion = false
                    }
                    .buttonStyle(.bordered)

                    Button {
                        app.selectRoute(option.id)
                        app.startPlannedRun()
                    } label: {
                        Label("Use this route", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .controlSize(.regular)

                Text("Distances verified with Apple Maps\(suggestion.model.map { " · \($0)" } ?? "")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
