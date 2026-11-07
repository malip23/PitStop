import SwiftUI

/// Pick one of the nearby real places to base a mock business on (name, address, and coordinates
/// get copied).
struct RealPlacePickerList: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let onPick: (RealPlace) -> Void

    @State private var query = ""

    var body: some View {
        List(filtered) { place in
            Button {
                onPick(place)
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: place.category.symbol)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color.secondary.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name).foregroundStyle(.primary)
                        Text([place.category.displayName, place.address].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if let here = app.currentLocation {
                        Text(Format.shortDistance(here.distance(from: place.location)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search nearby places")
        .overlay {
            if app.places.places.isEmpty {
                ContentUnavailableView("No nearby places yet", systemImage: "map",
                                       description: Text("Open the Run tab so PitStop can find places around you."))
            }
        }
        .navigationTitle("Link a real place")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filtered: [RealPlace] {
        let here = app.currentLocation
        return app.places.places
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted {
                guard let here else { return $0.name < $1.name }
                return here.distance(from: $0.location) < here.distance(from: $1.location)
            }
    }
}
