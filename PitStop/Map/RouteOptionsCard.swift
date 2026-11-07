import SwiftUI

/// Before the run: 2–3 route options to the destination, each with distance, time at the user's pace,
/// and fit to the goal. Tap one to highlight it on the map.
struct RouteOptionsCard: View {
    @Environment(AppState.self) private var app

    var body: some View {
        MaterialCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Routes", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("Goal \(Format.distance(target))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if app.isGeneratingRoutes {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Building routes that fit your goal…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if app.routeOptions.isEmpty {
                    HStack {
                        Label("No route found", systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Retry") { app.generateRoutes() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                } else {
                    aiStatus
                    crossingSummary
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(app.routeOptions) { option in
                                RouteChip(option: option, target: target,
                                          seconds: option.distance * pace,
                                          isSelected: option.id == app.selectedRoute?.id) {
                                    app.selectRoute(option.id)
                                }
                            }
                        }
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: app.selectedRouteID)
    }

    /// Route agent progress, its result (tap to reopen the card), or the "AI unavailable" note.
    @ViewBuilder private var aiStatus: some View {
        if let step = app.aiPlanningStep {
            HStack(spacing: 8) {
                ProgressView().controlSize(.mini)
                Label(step, systemImage: "sparkles").font(.caption).foregroundStyle(Theme.sky)
            }
        } else if let suggestion = app.aiSuggestion {
            Button {
                app.selectRoute(suggestion.option.id)
                app.showAISuggestion = true
            } label: {
                Label("AI pick: \(suggestion.title)", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.sky)
            }
            .buttonStyle(.plain)
        } else if let error = app.aiRouteError, app.preferences.aiRouteSuggestions {
            AIUnavailableNote(error: error)
        }
    }

    /// What safety-alert data the selected route has.
    @ViewBuilder private var crossingSummary: some View {
        if app.preferences.crossingAlerts {
            switch app.crossings.source {
            case .loading:
                Label("Checking crossings on this route…", systemImage: "figure.walk")
                    .font(.caption).foregroundStyle(.secondary)
            case .openStreetMap(let count):
                Label("\(count) crossing\(count == 1 ? "" : "s") from OpenStreetMap + turn alerts", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.secondary)
                    .symbolRenderingMode(.multicolor)
            case .turnsOnly:
                Label("Crossing data unavailable. Turn alerts only.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
            case .none:
                EmptyView()
            }
        }
    }

    private var target: Double { app.targetDistance(for: app.planForRouting) }
    private var pace: Double { app.planStore.pace(for: app.planForRouting.activity).secondsPerMeter }
}

private struct RouteChip: View {
    let option: RouteOption
    let target: Double
    let seconds: Double
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let fit = Int((option.fit(target: target) * 100).rounded())
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if option.kind == .ai {
                        Image(systemName: "sparkles").font(.caption2)
                    } else if option.kind == .generated {
                        Image(systemName: "wand.and.stars").font(.caption2)
                    }
                    Text(option.title).font(.caption.weight(.bold)).lineLimit(1)
                }
                Text(Format.distance(option.distance)).font(.headline.monospacedDigit())
                Text("\(Format.minutes(seconds)) · \(fit)% fit")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minWidth: 110, alignment: .leading)
            .background(isSelected ? AnyShapeStyle(Theme.coral.gradient) : AnyShapeStyle(Color(.secondarySystemBackground)),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: isSelected)
    }
}
