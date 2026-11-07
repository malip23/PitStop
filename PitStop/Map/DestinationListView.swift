import SwiftUI

/// Goal-matched destinations, sorted by fit: Off-Peak Quests first (with rewards), then everything
/// else. Real places say "Not on PitStop yet" and never show a reward.
struct DestinationListView: View {
    @Environment(AppState.self) private var app
    let plan: RunPlan
    /// Closes the whole Plan sheet (not just this pushed screen).
    let onFinish: () -> Void

    var body: some View {
        let finder = app.finder
        List {
            Section {
                goalSummary
            }

            switch finder.phase {
            case .searching(let message):
                searching(message)
            case .idle:
                searching("Waiting for your location…")
            case .failed(let message):
                ContentUnavailableView {
                    Label("No matches", systemImage: "map")
                } description: {
                    Text(message)
                }
                .listRowBackground(Color.clear)
            case .done:
                results(finder.matches)
            }
        }
        .navigationTitle("Destinations")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if finder.phase == .idle { app.findDestinations(for: plan) }
        }
        .onChange(of: finder.phase) { _, phase in
            // "Surprise me": as soon as results arrive, pick one and go back to the map.
            if phase == .done, plan.surpriseMe, let pick = app.surpriseMatch() {
                app.choose(pick, note: "Surprise pick")
                Haptics.success()
                onFinish()
            }
        }
    }

    private var goalSummary: some View {
        let target = app.targetDistance(for: plan)
        return HStack(spacing: 12) {
            Image(systemName: plan.activity.symbol)
                .font(.title2)
                .foregroundStyle(Theme.coral)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Format.distance(target)) \(plan.shape.displayName.lowercased()) \(plan.activity.displayName.lowercased())")
                    .font(.headline)
                Text("Showing real \(plan.activity == .bike ? "cycling" : "walking") routes within ±15% of your goal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func searching(_ message: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(message).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder private func results(_ matches: [DestinationMatch]) -> some View {
        let quests = matches.filter(\.hasQuest)
        let others = matches.filter { !$0.hasQuest }
        if !quests.isEmpty {
            Section("Off-Peak Quests") {
                ForEach(quests) { row($0) }
            }
        }
        if !others.isEmpty {
            Section {
                ForEach(others) { row($0) }
            } header: {
                Text("Fits your goal")
            } footer: {
                if matches.contains(where: \.isEstimate) {
                    Label("Some distances are estimates because routing was unavailable.", systemImage: "exclamationmark.triangle")
                }
            }
        }
    }

    private func row(_ match: DestinationMatch) -> some View {
        Button {
            app.choose(match)
            Haptics.tap()
            onFinish()
        } label: {
            DestinationMatchRow(match: match,
                                seconds: match.totalDistance * app.planStore.pace(for: plan.activity).secondsPerMeter)
        }
        .buttonStyle(.plain)
    }
}

/// One destination in the list.
private struct DestinationMatchRow: View {
    let match: DestinationMatch
    /// Estimated duration at the user's pace.
    let seconds: Double

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: match.destination.category.symbol)
                .foregroundStyle(match.destination.isPartner ? .white : .secondary)
                .frame(width: 40, height: 40)
                .background(match.destination.isPartner ? AnyShapeStyle(Theme.coral.gradient) : AnyShapeStyle(Color.secondary.opacity(0.12)),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(match.destination.name).font(.body.weight(.semibold)).lineLimit(1)
                if let reward = match.reward {
                    Label(reward, systemImage: "gift.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.coral)
                } else if !match.destination.isPartner {
                    Text("\(match.destination.category.displayName) · Not on PitStop yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(match.destination.category.displayName) · PitStop partner")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(detail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            FitBadge(fit: match.fit, extended: match.needsLongerRoute)
        }
        .contentShape(Rectangle())
    }

    private var detail: String {
        if match.needsLongerRoute {
            return "\(Format.distance(match.legDistance)) direct · route extended to fit"
        }
        let prefix = match.isEstimate ? "≈ " : ""
        return "\(prefix)\(Format.distance(match.totalDistance)) total · \(Format.minutes(seconds))"
    }
}

/// "96%" fit chip; "Extend" for quests that need a longer route.
private struct FitBadge: View {
    let fit: Double
    let extended: Bool

    var body: some View {
        Text(extended ? "Extend" : "\(Int((fit * 100).rounded()))%")
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(extended ? Theme.sky : (fit > 0.93 ? Theme.lime : Theme.coral))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((extended ? Theme.sky : (fit > 0.93 ? Theme.lime : Theme.coral)).opacity(0.15), in: Capsule())
    }
}
