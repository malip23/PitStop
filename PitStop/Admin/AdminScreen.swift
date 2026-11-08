import SwiftUI

/// Admin-only tab: stats, users (with role changes), businesses, and quests.
struct AdminScreen: View {
    enum Section: String, CaseIterable, Identifiable { case stats = "Stats", users = "Users", businesses = "Businesses", quests = "Quests"; var id: Self { self } }

    @Environment(AppState.self) private var app
    @State private var store = AdminStore()
    @State private var section: Section = .stats
    @State private var confirmWipe = false
    @State private var questFilter: Quest.Status? = nil

    var body: some View {
        NavigationStack {
            List {
                Picker("Section", selection: $section) {
                    ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if let error = store.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }

                switch section {
                case .stats: statsSection
                case .users: usersSection
                case .businesses: businessesSection
                case .quests: questsSection
                }
            }
            .navigationTitle("Admin")
            .refreshable { await store.refreshCounts() }
            .onAppear { store.start() }
            .onDisappear { store.stop() }
            .confirmationDialog("Delete all mock data?", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Delete mock businesses, quests, and visits", role: .destructive) {
                    Task { await store.deleteAllMockData(app.partners) }
                }
            } message: {
                Text("Removes every business marked DEMO, with its quests and check-ins. Real user accounts and run history are kept.")
            }
        }
    }

    // MARK: Stats

    private var statsSection: some View {
        SwiftUI.Section {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                tile("\(store.stats.totalUsers)", "Total users", "person.2.fill", Theme.sky)
                tile("\(store.stats.activeQuests)", "Active quests", "flag.checkered", Theme.coral)
                tile("\(store.stats.completedVisits)", "Verified visits", "checkmark.shield.fill", Theme.lime)
                tile("\(store.stats.totalRuns)", "Total runs", "figure.run", Theme.sun)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        } footer: {
            Text(store.isLoadingStats ? "Counting…" : "Pull to refresh. Visit and run counts are server-side aggregate queries.")
        }
    }

    private func tile(_ value: String, _ label: String, _ symbol: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(value).font(.title.weight(.bold).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Users

    private var usersSection: some View {
        SwiftUI.Section("\(store.users.count) users") {
            ForEach(store.users) { user in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName).font(.body.weight(.semibold))
                        Text(user.email).font(.caption).foregroundStyle(.secondary)
                        Text("Active \(user.lastActiveAt.formatted(.relative(presentation: .named)))")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if user.id == app.auth.uid {
                        Text("\(user.role.displayName) (you)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    } else {
                        Menu {
                            ForEach(UserRole.allCases) { role in
                                Button {
                                    if let uid = user.id { store.setRole(role, for: uid) }
                                } label: {
                                    if role == user.role { Label(role.displayName, systemImage: "checkmark") } else { Text(role.displayName) }
                                }
                            }
                        } label: {
                            Label(user.role.displayName, systemImage: "chevron.up.chevron.down")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .frame(minHeight: 44)
                        }
                        .accessibilityLabel("Role for \(user.displayName): \(user.role.displayName)")
                    }
                }
            }
        }
    }

    // MARK: Businesses

    private var businessesSection: some View {
        Group {
            SwiftUI.Section {
                ForEach(app.partners) { business in
                    HStack(spacing: 10) {
                        Image(systemName: business.category.symbol)
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Theme.coral.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(business.name).font(.body.weight(.semibold)).lineLimit(1)
                                if business.isMock { DemoBadge(compact: true) }
                            }
                            Text("Owner: \(store.user(business.ownerUid)?.email ?? "unknown")")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if business.isSlow {
                            Text("Slow").font(.caption.weight(.bold)).foregroundStyle(Theme.coral)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { Task { await store.deleteBusiness(business.id) } }
                    }
                }
            } header: {
                Text("\(app.partners.count) businesses")
            } footer: {
                Text("Swipe to delete a business with its quests and check-ins.")
            }
            SwiftUI.Section {
                Button("Delete all mock data", role: .destructive) { confirmWipe = true }
                    .disabled(!app.partners.contains(where: \.isMock))
            }
        }
    }

    // MARK: Quests

    private var questsSection: some View {
        let filtered = store.quests.filter { questFilter == nil || $0.status == questFilter }
        return SwiftUI.Section {
            Picker("Status", selection: $questFilter) {
                Text("All").tag(Quest.Status?.none)
                Text("Active").tag(Quest.Status?.some(.active))
                Text("Accepted").tag(Quest.Status?.some(.accepted))
                Text("Done").tag(Quest.Status?.some(.completed))
                Text("Expired").tag(Quest.Status?.some(.expired))
            }
            .pickerStyle(.menu)
            ForEach(filtered) { quest in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(app.partner(id: quest.businessId)?.name ?? "Deleted business").font(.body.weight(.semibold))
                        Spacer()
                        Text(quest.status.rawValue.capitalized)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(quest.isOpen ? Theme.coral : .secondary)
                    }
                    Text(quest.reward).font(.subheadline)
                    Text("Created \(quest.createdAt.formatted(date: .abbreviated, time: .shortened))\(quest.offerStats.map { " · \($0.shown) shown, \($0.accepted) accepted" } ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { store.deleteQuest(quest.id) }
                }
            }
        } header: {
            Text("\(filtered.count) quests")
        }
    }
}
