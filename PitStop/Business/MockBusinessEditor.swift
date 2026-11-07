import CoreLocation
import SwiftUI

/// Create or edit a mock (demo) partner business.
///
/// There are three ways to choose the location: long-press a map, use the current location, or link
/// a nearby real place (copies its name, address, and coordinates).
struct MockBusinessEditor: View {
    enum LocationSource: String, CaseIterable, Identifiable {
        case pin = "Drop pin", current = "Current", realPlace = "Real place"
        var id: Self { self }
    }

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    /// The business being edited, or nil to create a new one.
    let existing: Business?
    var onSaved: (Business) -> Void = { _ in }

    @State private var name = ""
    @State private var category: BusinessCategory = .cafe
    @State private var reward = ""
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var address: String?
    @State private var linkedRealPlaceName: String?
    @State private var source: LocationSource = .pin
    @State private var isGeocoding = false
    @State private var confirmDelete = false
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Business") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    Picker("Category", selection: $category) {
                        ForEach(BusinessCategory.allCases, id: \.self) { category in
                            Label(category.displayName, systemImage: category.symbol).tag(category)
                        }
                    }
                }

                Section {
                    TextField("e.g. Free cold brew", text: $reward)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(category.suggestedRewards, id: \.self) { idea in
                                Button(idea) { reward = idea }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                    }
                } header: {
                    Text("Reward")
                } footer: {
                    Text("Runners unlock this when they check in during your slow hours.")
                }

                Section("Location") {
                    Picker("Source", selection: $source) {
                        ForEach(LocationSource.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch source {
                    case .pin:
                        LocationPickerMap(coordinate: $coordinate) { dropped in
                            linkedRealPlaceName = nil
                            lookUpAddress(for: dropped)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    case .current:
                        Button {
                            useCurrentLocation()
                        } label: {
                            Label("Use my current location", systemImage: "location.fill")
                        }
                        .disabled(app.currentLocation == nil)
                    case .realPlace:
                        NavigationLink {
                            RealPlacePickerList { link($0) }
                        } label: {
                            Label(linkedRealPlaceName ?? "Choose a nearby place", systemImage: "link")
                        }
                    }

                    locationSummary
                }

                if existing != nil {
                    Section {
                        Button("Delete Business", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Mock Business" : "Edit Business")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .confirmationDialog("Delete \(name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let existing { app.deleteBusiness(id: existing.id) }
                    dismiss()
                }
            } message: {
                Text("Its quests are removed too. This can't be undone.")
            }
            .onAppear(perform: loadExisting)
        }
    }

    @ViewBuilder private var locationSummary: some View {
        if let coordinate {
            VStack(alignment: .leading, spacing: 2) {
                if isGeocoding {
                    Label("Looking up address…", systemImage: "hourglass").font(.subheadline)
                } else {
                    Label(address ?? "Unknown address", systemImage: "mappin.and.ellipse").font(.subheadline)
                }
                Text(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let linkedRealPlaceName {
                    Text("Linked to real place: \(linkedRealPlaceName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("No location chosen yet").foregroundStyle(.secondary)
        }
    }

    private var canSave: Bool {
        coordinate != nil
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !reward.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: Actions

    private func loadExisting() {
        guard !didLoad else { return }
        didLoad = true
        if let existing {
            name = existing.name
            category = existing.category
            reward = existing.reward
            coordinate = existing.coordinate
            address = existing.address
            linkedRealPlaceName = existing.linkedRealPlaceName
            source = existing.linkedRealPlaceName != nil ? .realPlace : .pin
        } else {
            reward = category.suggestedRewards.first ?? ""
        }
    }

    private func useCurrentLocation() {
        guard let here = app.currentLocation?.coordinate else { return }
        coordinate = here
        linkedRealPlaceName = nil
        lookUpAddress(for: here)
    }

    private func link(_ place: RealPlace) {
        coordinate = place.coordinate
        address = place.address
        linkedRealPlaceName = place.name
        // New businesses take the real place's name; edits keep a name the owner already chose.
        if name.isEmpty || existing == nil { name = place.name }
        // Swap in a matching reward idea, unless the owner wrote a custom reward.
        let rewardWasSuggestion = reward.isEmpty || category.suggestedRewards.contains(reward)
        category = place.category
        if rewardWasSuggestion { reward = place.category.suggestedRewards.first ?? reward }
    }

    private func lookUpAddress(for coordinate: CLLocationCoordinate2D) {
        isGeocoding = true
        Task {
            address = await ReverseGeocoder.address(for: coordinate)
            isGeocoding = false
        }
    }

    private func save() {
        guard let coordinate else { return }
        var business = existing ?? Business(name: "", category: category, latitude: 0, longitude: 0, reward: "")
        business.name = name.trimmingCharacters(in: .whitespaces)
        business.category = category
        business.reward = reward.trimmingCharacters(in: .whitespaces)
        business.latitude = coordinate.latitude
        business.longitude = coordinate.longitude
        business.address = address
        business.linkedRealPlaceName = linkedRealPlaceName
        business.isMock = true
        app.saveBusiness(business)
        onSaved(business)
        dismiss()
    }
}
