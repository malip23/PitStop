import SwiftData
import SwiftUI

/// Runner-only tab: places you've checked in at (Visited, built from run history) and places you've
/// saved for later (Future Places), as a list or a map.
struct MyPlacesScreen: View {
    enum Mode: String, CaseIterable, Identifiable { case list = "List", map = "Map"; var id: Self { self } }

    @Environment(AppState.self) private var app
    /// Switches to the Run tab after "Plan a run here".
    var onPlanRun: () -> Void = {}

    @Query(filter: #Predicate<RunRecord> { $0.checkedIn }, sort: \RunRecord.date, order: .reverse)
    private var checkedInRuns: [RunRecord]
    @Query(sort: \SavedPlace.savedAt, order: .reverse) private var saved: [SavedPlace]
    @State private var mode: Mode = .list

    var body: some View {
        let visited = VisitedPlace.from(checkedInRuns)
        NavigationStack {
            Group {
                switch mode {
                case .list: list(visited)
                case .map: PlacesMapView(visited: visited, future: saved)
                }
            }
            .navigationTitle("My Places")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }
        }
    }

    private func list(_ visited: [VisitedPlace]) -> some View {
        List {
            Section {
                if visited.isEmpty {
                    emptyRow("No visits yet", "Run to a destination and stay 10 seconds to check in.", "figure.run")
                }
                ForEach(visited) { place in
                    HStack(spacing: 12) {
                        MiniMap(point: place.point)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(place.name).font(.body.weight(.semibold)).lineLimit(1)
                                if place.isPartner {
                                    Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(Theme.coral)
                                }
                            }
                            Label(place.category.displayName, systemImage: place.category.symbol)
                                .font(.caption).foregroundStyle(.secondary)
                            Text("\(place.visitCount) visit\(place.visitCount == 1 ? "" : "s") · last \(place.lastVisit.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            } header: {
                Label("Visited (\(visited.count))", systemImage: "checkmark.circle.fill")
            }

            Section {
                if saved.isEmpty {
                    emptyRow("Nothing saved yet", "Tap \"Save for later\" on any place on the map.", "bookmark")
                }
                ForEach(saved) { place in
                    HStack(spacing: 12) {
                        MiniMap(point: place.point, tint: Theme.sky)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(place.name).font(.body.weight(.semibold)).lineLimit(1)
                            Label(place.category.displayName, systemImage: place.category.symbol)
                                .font(.caption).foregroundStyle(.secondary)
                            Button {
                                app.planRun(to: place.destination)
                                onPlanRun()
                            } label: {
                                Label("Plan a run here", systemImage: "figure.run")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .tint(Theme.coral)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .onDelete { offsets in
                    for index in offsets { app.history.removeSavedPlace(id: saved[index].id) }
                }
            } header: {
                Label("Future Places (\(saved.count))", systemImage: "bookmark.fill")
            }
        }
    }

    private func emptyRow(_ title: String, _ detail: String, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.secondary).frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
