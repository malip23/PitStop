import SwiftData
import SwiftUI

/// Rewards tab, in three clearly separate groups:
/// - **Passport:** digital stamps for new places (collectibles)
/// - **Badges:** milestones, earned or locked with progress
/// - **Partner rewards:** real perks from businesses
/// Run History is linked at the bottom.
struct RewardsScreen: View {
    @Query(sort: \Stamp.earnedAt, order: .reverse) private var stamps: [Stamp]
    @Query private var earnedBadges: [EarnedBadge]
    @Query(sort: \EarnedReward.earnedAt, order: .reverse) private var rewards: [EarnedReward]
    @Query private var runs: [RunRecord]

    var body: some View {
        let stats = RewardsEngine.stats(runs: runs, stampCount: stamps.count)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    summary(stats)
                    passport
                    badges(stats)
                    partnerRewards
                    historyLink
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Rewards")
        }
    }

    // MARK: Sections

    private func summary(_ stats: RewardStats) -> some View {
        HStack(spacing: 10) {
            summaryTile("\(stamps.count)", "Stamps", "seal.fill", Theme.coral)
            summaryTile("\(earnedBadges.count)/\(BadgeKind.allCases.count)", "Badges", "rosette", Theme.sun)
            summaryTile(String(format: "%.1f", stats.verifiedMiles), "Verified mi", "figure.run", Theme.lime)
        }
    }

    private func summaryTile(_ value: String, _ label: String, _ symbol: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(value).font(.title3.weight(.bold).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var passport: some View {
        VStack(alignment: .leading, spacing: 12) {
            header("Passport", "Digital stamps: one for each new place you reach on a verified run.")
            if stamps.isEmpty {
                emptyCard("No stamps yet", "Check in somewhere new to earn your first stamp.", "seal")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 14)], spacing: 16) {
                    ForEach(stamps) { stamp in
                        PassportStampView(name: stamp.placeName, category: stamp.category,
                                          date: stamp.earnedAt, seed: stamp.id)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
        }
    }

    private func badges(_ stats: RewardStats) -> some View {
        let earned = Dictionary(uniqueKeysWithValues: earnedBadges.map { ($0.id, $0.earnedAt) })
        return VStack(alignment: .leading, spacing: 12) {
            header("Badges", "Milestones from verified runs.")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                // Earned first, then locked by how close they are.
                ForEach(BadgeKind.allCases.sorted { a, b in
                    let ea = earned[a.rawValue] != nil, eb = earned[b.rawValue] != nil
                    if ea != eb { return ea }
                    return a.value(in: stats) / a.target > b.value(in: stats) / b.target
                }) { kind in
                    BadgeTile(kind: kind, stats: stats, earnedAt: earned[kind.rawValue])
                }
            }
        }
    }

    private var partnerRewards: some View {
        VStack(alignment: .leading, spacing: 12) {
            header("Partner rewards", "Real perks from PitStop businesses. Show one at the counter, then mark it used.")
            if rewards.isEmpty {
                emptyCard("No partner rewards yet", "Accept an Off-Peak Quest, run there, and check in.", "gift")
            } else {
                VStack(spacing: 10) {
                    ForEach(rewards) { PartnerRewardRow(reward: $0) }
                }
            }
        }
    }

    private var historyLink: some View {
        NavigationLink {
            RunHistoryView()
        } label: {
            HStack {
                Label("Run History", systemImage: "clock.arrow.circlepath").font(.body.weight(.semibold))
                Spacer()
                Text("\(runs.count) runs").foregroundStyle(.secondary)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Helpers

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title2.weight(.bold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func emptyCard(_ title: String, _ detail: String, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// A partner reward "ticket" with a mark-as-used action.
struct PartnerRewardRow: View {
    @Bindable var reward: EarnedReward

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: reward.redeemed ? "checkmark" : "gift.fill")
                .font(.title3)
                .foregroundStyle(reward.redeemed ? .secondary : Color.black.opacity(0.8))
                .frame(width: 44, height: 44)
                .background(reward.redeemed ? AnyShapeStyle(Color.secondary.opacity(0.15)) : AnyShapeStyle(Theme.sun),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(reward.reward).font(.headline).strikethrough(reward.redeemed)
                Text(reward.businessName).font(.subheadline).foregroundStyle(.secondary)
                Text("Earned \(reward.earnedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(reward.redeemed ? "Used" : "Use") { reward.redeemed = true }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(reward.redeemed)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(reward.redeemed ? 0.6 : 1)
    }
}
