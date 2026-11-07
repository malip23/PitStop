import MapKit
import SwiftUI

/// The hero screen: a full-screen map with partner businesses, real nearby places, the run trace,
/// and floating cards.
struct RunMapScreen: View {
    @Environment(AppState.self) private var app
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selection: MapSelection?
    @State private var showPlanSheet = false

    var body: some View {
        Map(position: $camera, selection: $selection) {
            UserAnnotation()

            // Breadcrumb of where the runner has been.
            if app.run.trace.count > 1 {
                MapPolyline(coordinates: app.run.trace.map(\.coordinate))
                    .stroke(.blue.opacity(0.6), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }

            // Until real routes exist (section C), a dashed line points at the destination.
            if let destination = app.destination, let here = app.currentLocation {
                MapPolyline(coordinates: [here.coordinate, destination.coordinate])
                    .stroke(Color.accentColor.opacity(0.7),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 8]))
            }

            // Real places first so partner pins draw on top of them.
            ForEach(app.places.places) { place in
                Annotation(place.name, coordinate: place.coordinate) {
                    RealPlacePin(place: place, isSelected: selection == .place(place.id))
                }
                .tag(MapSelection.place(place.id))
                .annotationTitles(.hidden)
            }

            ForEach(app.partners) { business in
                Annotation(business.name, coordinate: business.coordinate, anchor: .bottom) {
                    BusinessPin(business: business,
                                isSelected: selection == .partner(business.id),
                                hasQuest: business.isSlow && app.questStore.openQuest(for: business.id) != nil)
                }
                .tag(MapSelection.partner(business.id))
            }

            if let destination = app.destination {
                Annotation("Destination", coordinate: destination.coordinate, anchor: .bottom) {
                    DestinationFlag()
                        .offset(y: destination.isPartner ? -52 : -14)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .overlay(alignment: .top) { searchStatus }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                selectionCard
                if let accepted = app.acceptedQuest, selection != .partner(accepted.business.id) {
                    AcceptedQuestCard(quest: accepted.quest, business: accepted.business)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let destination = app.destination, selection == nil {
                    DestinationCard(destination: destination)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if !app.location.isAuthorized {
                    LocationPermissionCard()
                }
                RunStatsCard { showPlanSheet = true }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            .animation(.snappy, value: selection)
            .animation(.snappy, value: app.acceptedQuest?.quest.id)
            .animation(.snappy, value: app.destination?.id)
        }
        .sheet(isPresented: $showPlanSheet) {
            PlanRunSheet()
        }
        .onChange(of: app.mapFocus) { _, target in
            guard let target else { return }
            focus(on: target)
            app.mapFocus = nil
        }
        .onAppear {
            if app.location.authorization == .notDetermined {
                app.location.requestWhenInUse()
            } else {
                app.location.start()
            }
        }
    }

    /// Frames both the runner and the target pin (after accepting a quest or a surprise pick).
    private func focus(on target: MapSelection) {
        let coordinate: CLLocationCoordinate2D
        switch target {
        case .partner(let id):
            guard let business = app.partner(id: id) else { return }
            coordinate = business.coordinate
            selection = target
        case .place(let id):
            guard let place = app.places.place(id: id) else { return }
            coordinate = place.coordinate
        }
        let here = app.currentLocation?.coordinate ?? coordinate
        let center = CLLocationCoordinate2D(latitude: (here.latitude + coordinate.latitude) / 2,
                                            longitude: (here.longitude + coordinate.longitude) / 2)
        let span = max(here.distance(to: coordinate) * 2.6, 800)
        withAnimation(.easeInOut(duration: 0.8)) {
            camera = .camera(MapCamera(centerCoordinate: center, distance: span))
        }
    }

    @ViewBuilder private var selectionCard: some View {
        switch selection {
        case .partner(let id):
            if let business = app.partner(id: id) {
                PartnerDetailCard(business: business) { selection = nil }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        case .place(let id):
            if let place = app.places.place(id: id) {
                RealPlaceDetailCard(place: place) { selection = nil }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        case nil:
            EmptyView()
        }
    }

    /// Small capsule at the top while searching, or if the search failed.
    @ViewBuilder private var searchStatus: some View {
        if app.places.isSearching {
            Label("Finding nearby places…", systemImage: "magnifyingglass")
                .statusCapsule()
        } else if let error = app.places.lastError, app.places.places.isEmpty {
            Label(error, systemImage: "wifi.exclamationmark")
                .statusCapsule()
        }
    }
}

private extension View {
    func statusCapsule() -> some View {
        self.font(.footnote.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}
