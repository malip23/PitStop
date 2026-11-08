import SwiftUI

/// The business owner's dashboard: flip "We're slow right now," tune the reward, and see the
/// quest's status. Owners only ever see quest and visit info, never runner health data.
struct BusinessDashboardView: View {
    @Environment(AppState.self) private var app
    let businessID: Business.ID

    @State private var rewardDraft = ""
    @State private var showEditor = false
    @FocusState private var rewardFocused: Bool

    var body: some View {
        if let business = app.partner(id: businessID) {
            ScrollView {
                VStack(spacing: 16) {
                    header(business)
                    slowCard(business)
                    rewardCard(business)
                    questStatusCard(business)
                    Label("You'll see visits and arrival times only, never runner health data or routes.",
                          systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(business.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Edit") { showEditor = true }
            }
            .sheet(isPresented: $showEditor) {
                MockBusinessEditor(existing: business)
            }
            .onAppear { rewardDraft = business.reward }
            .sensoryFeedback(.impact(weight: .heavy), trigger: business.isSlow)
        } else {
            ContentUnavailableView("Business deleted", systemImage: "trash")
        }
    }

    // MARK: Cards

    private func header(_ business: Business) -> some View {
        DashboardCard {
            HStack(spacing: 14) {
                Image(systemName: business.category.symbol)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(business.name).font(.title3.weight(.semibold))
                        if business.isMock { DemoBadge() }
                    }
                    Text(business.category.displayName).foregroundStyle(.secondary)
                    if let address = business.address {
                        Text(address).font(.caption).foregroundStyle(.secondary)
                    }
                    if let linked = business.linkedRealPlaceName {
                        Label("Linked to \(linked)", systemImage: "link")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func slowCard(_ business: Business) -> some View {
        DashboardCard(highlighted: business.isSlow) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { business.isSlow },
                    set: { app.setSlow($0, businessID: business.id) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("We're slow right now")
                            .font(.title3.weight(.bold))
                        Text(business.isSlow ? "Off-Peak Quest is live" : "Turn on to invite nearby runners")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.accentColor)

                if business.isSlow, let since = business.slowSince {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Label("Slow for \(Format.minutes(context.date.timeIntervalSince(since)))",
                              systemImage: "clock")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .animation(.snappy, value: business.isSlow)
    }

    private func rewardCard(_ business: Business) -> some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Reward", systemImage: "gift.fill")
                    .font(.headline)
                TextField("e.g. Free cold brew", text: $rewardDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($rewardFocused)
                    .submitLabel(.done)
                    .onSubmit { commitReward(business) }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(business.category.suggestedRewards, id: \.self) { idea in
                            Button(idea) {
                                rewardDraft = idea
                                commitReward(business)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                if rewardDraft != business.reward {
                    Button("Save reward") { commitReward(business) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
    }

    private func questStatusCard(_ business: Business) -> some View {
        let quest = app.questStore.openQuest(for: business.id)
        let visits = app.questStore.recentVisits(to: business.id)
        return DashboardCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Quest status", systemImage: "flag.checkered").font(.headline)
                switch quest?.status {
                case .accepted:
                    Label("A runner accepted. They're on the way!", systemImage: "figure.run")
                        .foregroundStyle(.green)
                    if let quest, let eta = quest.etaSeconds, let updated = quest.etaUpdatedAt {
                        // Live countdown from the runner's last ETA report.
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let left = max(0, updated.addingTimeInterval(eta).timeIntervalSince(context.date))
                            Label(left < 30 ? "Runner arriving now" : "Runner arriving in \(Format.duration(left))",
                                  systemImage: "timer")
                                .font(.title3.weight(.bold).monospacedDigit())
                                .foregroundStyle(Theme.coral)
                                .contentTransition(.numericText(countsDown: true))
                        }
                    }
                case .active:
                    Label("Live. Waiting for a runner to accept.", systemImage: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(Color.accentColor)
                default:
                    Text("No active quest.").foregroundStyle(.secondary)
                }
                if let stats = quest?.offerStats {
                    offerActivity(stats)
                }
                Text("\(visits) quest visit\(visits == 1 ? "" : "s") in the last 30 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                RecentVisitsList(businessID: business.id)
            }
        }
    }

    /// What happened to the timed (\(Int(OfferTiming.countdown)) s) offer popups runners saw.
    private func offerActivity(_ stats: OfferStats) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let outcome = stats.lastOutcome, let at = stats.lastOutcomeAt {
                Label(lastOutcomeText(outcome, at: at), systemImage: outcomeSymbol(outcome))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(outcomeColor(outcome))
            }
            HStack(spacing: 14) {
                Label("\(stats.shown) shown", systemImage: "eye")
                Label("\(stats.accepted) accepted", systemImage: "checkmark.circle")
                Label("\(stats.expired) expired", systemImage: "timer")
                Label("\(stats.dismissed) passed", systemImage: "xmark.circle")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func lastOutcomeText(_ outcome: OfferStats.Outcome, at date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        switch outcome {
        case .shown: return "Offer showing to a runner now (\(time))"
        case .accepted: return "Offer accepted at \(time)"
        case .expired: return "Offer expired at \(time): no answer in \(Int(OfferTiming.countdown)) s"
        case .dismissed: return "Runner passed at \(time)"
        }
    }

    private func outcomeSymbol(_ outcome: OfferStats.Outcome) -> String {
        switch outcome {
        case .shown: "eye.fill"
        case .accepted: "checkmark.circle.fill"
        case .expired: "timer"
        case .dismissed: "xmark.circle.fill"
        }
    }

    private func outcomeColor(_ outcome: OfferStats.Outcome) -> Color {
        switch outcome {
        case .shown: Theme.sky
        case .accepted: .green
        case .expired: .orange
        case .dismissed: .secondary
        }
    }

    private func commitReward(_ business: Business) {
        let trimmed = rewardDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != business.reward else { return }
        var updated = business
        updated.reward = trimmed
        app.saveBusiness(updated)
        rewardFocused = false
    }
}

/// Rounded card used on the business dashboard.
private struct DashboardCard<Content: View>: View {
    var highlighted = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: highlighted ? 2 : 0)
            )
    }
}
