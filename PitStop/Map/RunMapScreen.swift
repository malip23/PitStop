import MapKit
import SwiftUI

/// The hero screen: a full-screen map with partner businesses, real nearby places, the run trace,
/// and floating cards.
struct RunMapScreen: View {
    @Environment(AppState.self) private var app
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selection: MapSelection?
    @State private var showPlanSheet = false
    @State private var showLegend = false
    @State private var showQuests = false
    @State private var showSuggestions = false
    @State private var questsDetent: PresentationDetent = .medium
    /// Measured heights of the top and bottom overlays and the map, used to keep the route and
    /// the user marker in the visible gap between them.
    @State private var topInset: CGFloat = 0
    @State private var bottomInset: CGFloat = 0
    @State private var mapHeight: CGFloat = 800
    @State private var lastFramedInset: CGFloat = 0
    /// Last camera the map reported. Lets animations keep the current zoom, rotation, and pitch.
    @State private var lastCamera: MapCamera?
    /// Set when code (not a tap) changes the selection, so we don't also re-center on the pin.
    @State private var skipSelectionCamera = false
    /// While navigating, the camera follows the runner (toggle with the follow button).
    @State private var followRunner = true

    var body: some View {
        Map(position: $camera, selection: $selection) {
            if app.navigation.isNavigating {
                // Navigating: covered part of the route in lime, what's left in the coral gradient.
                if app.navigation.remainingCoordinates.count > 1 {
                    GlowingRoute(coordinates: app.navigation.remainingCoordinates)
                }
                if app.navigation.completedCoordinates.count > 1 {
                    GlowingRoute(coordinates: app.navigation.completedCoordinates,
                                 colors: Theme.completedGradient, lineWidth: 7)
                }
            } else {
                // Free run: the path covered so far.
                if app.run.trace.count > 1 {
                    GlowingRoute(coordinates: app.run.trace.map(\.coordinate),
                                 colors: Theme.completedGradient, lineWidth: 6)
                }
                // Before the run: every route option, with the selected one highlighted.
                ForEach(app.routeOptions.filter { $0.id != app.selectedRoute?.id }) { option in
                    MapPolyline(coordinates: option.coordinates)
                        .stroke(Theme.coral.opacity(0.35), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                if let selected = app.selectedRoute {
                    GlowingRoute(coordinates: selected.coordinates)
                } else if let destination = app.destination, let here = app.currentLocation {
                    // While routes load: a dashed line toward the destination.
                    MapPolyline(coordinates: [here.coordinate, destination.coordinate])
                        .stroke(Theme.coral.opacity(0.8),
                                style: StrokeStyle(lineWidth: 3.5, lineCap: .round, dash: [6, 8]))
                }
            }

            // Real places first so partner pins draw on top of them.
            ForEach(app.places.places) { place in
                Annotation(place.name, coordinate: place.coordinate) {
                    RealPlacePin(place: place, status: app.pinStatus(for: place, selected: selection == .place(place.id)))
                }
                .tag(MapSelection.place(place.id))
                .annotationTitles(.hidden)
            }

            // Goal-matched places from ring searches that aren't in the nearby cache.
            ForEach(extraMatchPlaces) { place in
                Annotation(place.name, coordinate: place.coordinate) {
                    RealPlacePin(place: place, status: app.pinStatus(for: place, selected: selection == .place(place.id)))
                }
                .tag(MapSelection.place(place.id))
                .annotationTitles(.hidden)
            }

            ForEach(app.partners) { business in
                Annotation(business.name, coordinate: business.coordinate, anchor: .bottom) {
                    BusinessPin(business: business,
                                status: app.pinStatus(for: business, selected: selection == .partner(business.id)))
                }
                .tag(MapSelection.partner(business.id))
            }

            // Destination that isn't one of the pins above (e.g. its place dropped out of the search cache).
            if let destination = app.destination, !destinationHasPin(destination) {
                Annotation("Destination", coordinate: destination.coordinate, anchor: .bottom) {
                    DestinationFlag()
                }
                .annotationTitles(.hidden)
            }

            // Upcoming crosswalks, signals, and intersections (next 300 m) while navigating.
            if app.navigation.isNavigating && app.preferences.crossingAlerts {
                ForEach(app.crossings.upcomingPoints) { point in
                    Annotation(point.kind.title, coordinate: point.coordinate) {
                        CrossingMarker(point: point, isActive: app.crossings.activeAlert?.id == point.id)
                    }
                    .annotationTitles(.hidden)
                }
            }

            // Custom "you" marker with heading arrow. Uses the app's location, so Demo Mode moves it too.
            if let here = app.currentLocation {
                Annotation("You", coordinate: here.coordinate) {
                    UserLocationMarker(heading: app.userHeading, mapHeading: lastCamera?.heading ?? 0)
                }
                .annotationTitles(.hidden)
            }
        }
        .background(GeometryReader { geo in
            Color.clear.onAppear { mapHeight = geo.size.height }
                .onChange(of: geo.size.height) { _, h in mapHeight = h }
        })
        // Muted base map without Apple's POI icons, so our own pins carry the design.
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            lastCamera = context.camera
        }
        .onChange(of: selection) { _, newValue in
            if skipSelectionCamera { skipSelectionCamera = false; return }
            if let newValue { centerCamera(on: newValue) }
        }
        .onChange(of: app.run.state) { _, state in
            if state == .running { followRunner = true; cameraForRunStart() }
        }
        .onChange(of: app.currentLocation?.timestamp) { _, _ in
            followCameraIfNeeded()
        }
        .onChange(of: app.selectedRouteID) { _, _ in
            if let route = app.selectedRoute { frame(route) }
        }
        .onChange(of: bottomInset) { _, inset in
            // A card appeared or grew: re-fit the planned route so it stays above it.
            guard !app.run.isActive, abs(inset - lastFramedInset) > 40, let route = app.selectedRoute else { return }
            lastFramedInset = inset
            frame(route)
        }
        .overlay(alignment: .topLeading) {
            if !app.navigation.isNavigating {
                VStack(spacing: 10) {
                    legendButton
                    if app.role == .runner {
                        questsButton
                        suggestionsButton
                    }
                }
            }
        }
        // Top: one compact navigation row, then the top popup slot (safety / narration pills).
        .safeAreaInset(edge: .top) {
            VStack(spacing: 6) {
                if app.navigation.isNavigating {
                    NavigationBanner(followRunner: $followRunner)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    searchStatus
                }
                if app.selectedTab == .run {
                    PopupHost(placement: .top)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 2)
            .animation(.snappy, value: app.navigation.isNavigating)
            .measureHeight { topInset = $0 }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if app.selectedTab == .run {
                    PopupHost(placement: .bottom)
                }
                selectionCard
                if app.navigation.isNavigating {
                    // The navigation banner covers destination info during the run.
                } else if let accepted = app.acceptedQuest, selection != .partner(accepted.business.id) {
                    AcceptedQuestCard(quest: accepted.quest, business: accepted.business)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let destination = app.destination, selection == nil {
                    DestinationCard(destination: destination)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if app.destination != nil, !app.run.isActive, app.run.state != .finished {
                    if let suggestion = app.aiSuggestion, app.showAISuggestion {
                        AIRouteSuggestionCard(suggestion: suggestion)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        RouteOptionsCard()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                if !app.location.isAuthorized {
                    LocationPermissionCard()
                }
                RunStatsCard { showPlanSheet = true }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .measureHeight { bottomInset = $0 }
            .animation(.snappy, value: selection)
            .animation(.snappy, value: app.acceptedQuest?.quest.id)
            .animation(.snappy, value: app.destination?.id)
            .animation(.snappy, value: app.showAISuggestion)
            .animation(.snappy, value: app.aiSuggestion?.option.id)
        }
        .sheet(isPresented: $showPlanSheet) {
            PlanRunSheet()
        }
        .sheet(isPresented: $showLegend) {
            MapLegendSheet()
        }
        .sheet(isPresented: $showSuggestions) {
            SuggestionsSheet(compact: app.run.isActive)
        }
        .onChange(of: app.currentLocation == nil) { _, _ in app.refreshRecommendations() }
        .sheet(isPresented: $showQuests) {
            QuestsScreen(onAccepted: { showQuests = false })
                .presentationDetents([.height(120), .medium, .large], selection: $questsDetent)
                .presentationBackgroundInteraction(.enabled(upThrough: .height(120)))
                .presentationDragIndicator(.visible)
        }
        .onChange(of: showQuests) { _, open in
            // During a run, sheets open at the smallest size so the route stays visible.
            if open { questsDetent = app.run.isActive ? .height(120) : .medium }
        }
        .onChange(of: app.mapFocus) { _, target in
            guard let target else { return }
            focus(on: target)
            app.mapFocus = nil
        }
        .onAppear {
            // During first launch, onboarding asks for location (with context) instead.
            if app.location.authorization != .notDetermined {
                app.location.start()
            }
            app.refreshRecommendations()
        }
    }

    /// Goal matches and recommendations that aren't in the nearby-places cache (de-duplicated).
    private var extraMatchPlaces: [RealPlace] {
        var seen = Set(app.places.places.map(\.id))
        return (app.finder.matches.compactMap(\.realPlace) + app.recommendations.items.compactMap(\.realPlace))
            .filter { seen.insert($0.id).inserted }
    }

    // MARK: Camera

    /// Camera center that puts `point` in the middle of the VISIBLE map (between the top and bottom
    /// overlays) instead of the middle of the screen. "Up" on screen is `heading`, so the camera center
    /// moves backwards by half the overlay imbalance, converted from points to meters.
    private func visibleCenter(for point: CLLocationCoordinate2D, heading: Double, distance: Double) -> CLLocationCoordinate2D {
        let shiftPoints = (bottomInset - topInset) / 2
        guard abs(shiftPoints) > 4 else { return point }
        let metersPerPoint = distance * 0.9 / max(mapHeight, 1)   // rough, fine at running zoom levels
        return point.offset(bearingDegrees: heading + 180, meters: shiftPoints * metersPerPoint)
    }

    /// Keeps the runner in the visible middle, facing their direction of travel, while navigating.
    private func followCameraIfNeeded() {
        guard app.navigation.isNavigating, followRunner, app.run.state == .running,
              let here = app.currentLocation?.coordinate else { return }
        let heading = app.userHeading ?? lastCamera?.heading ?? 0
        withAnimation(.linear(duration: 0.9)) {
            camera = .camera(MapCamera(centerCoordinate: visibleCenter(for: here, heading: heading, distance: 550),
                                       distance: 550, heading: heading, pitch: 50))
        }
    }

    /// Fits a route option in the visible area (extra room under the bottom cards and the top bar).
    private func frame(_ route: RouteOption) {
        guard !route.coordinates.isEmpty else { return }
        let rect = MKPolyline(coordinates: route.coordinates, count: route.coordinates.count).boundingMapRect
        var padded = rect.insetBy(dx: -rect.width * 0.2, dy: -rect.height * 0.2)
        let visible = max(mapHeight - topInset - bottomInset, 120)
        let southExtra = padded.height * Double(bottomInset / visible)
        let northExtra = padded.height * Double(topInset / visible)
        padded = MKMapRect(x: padded.origin.x, y: padded.origin.y - northExtra,
                           width: padded.width, height: padded.height + northExtra + southExtra)
        withAnimation(.smooth(duration: 0.7)) {
            camera = .rect(padded)
        }
    }

    private func coordinate(of target: MapSelection) -> CLLocationCoordinate2D? {
        switch target {
        case .partner(let id): app.partner(id: id)?.coordinate
        case .place(let id): app.realPlace(id: id)?.coordinate
            ?? (app.destination?.id == id ? app.destination?.coordinate : nil)
        }
    }

    private func destinationHasPin(_ destination: PlannedDestination) -> Bool {
        destination.isPartner ? app.partner(id: destination.id) != nil : app.realPlace(id: destination.id) != nil
    }

    /// Smoothly glides to a tapped pin, keeping the current zoom, rotation, and tilt.
    private func centerCamera(on target: MapSelection) {
        guard let coordinate = coordinate(of: target) else { return }
        let distance = min(lastCamera?.distance ?? 1500, 2500)
        let heading = lastCamera?.heading ?? 0
        withAnimation(.smooth(duration: 0.6)) {
            camera = .camera(MapCamera(centerCoordinate: visibleCenter(for: coordinate, heading: heading, distance: distance),
                                       distance: distance, heading: heading, pitch: lastCamera?.pitch ?? 0))
        }
    }

    /// When a run starts, swoop into a tilted view facing the way you're going: framing you and the
    /// destination if there is one, otherwise close around you.
    private func cameraForRunStart() {
        guard let here = app.currentLocation?.coordinate else { return }
        guard let destination = app.destination?.coordinate else {
            let heading = app.userHeading ?? 0
            withAnimation(.easeInOut(duration: 1.2)) {
                camera = .camera(MapCamera(centerCoordinate: visibleCenter(for: here, heading: heading, distance: 900),
                                           distance: 900, heading: heading, pitch: 50))
            }
            return
        }
        let center = CLLocationCoordinate2D(latitude: (here.latitude + destination.latitude) / 2,
                                            longitude: (here.longitude + destination.longitude) / 2)
        let distance = max(here.distance(to: destination) * 2.4, 900)
        let heading = here.bearing(to: destination)
        withAnimation(.easeInOut(duration: 1.2)) {
            camera = .camera(MapCamera(centerCoordinate: visibleCenter(for: center, heading: heading, distance: distance),
                                       distance: distance, heading: heading, pitch: 45))
        }
    }

    /// Frames both the runner and the target pin (after accepting a quest or a surprise pick).
    private func focus(on target: MapSelection) {
        let coordinate: CLLocationCoordinate2D
        switch target {
        case .partner(let id):
            guard let business = app.partner(id: id) else { return }
            coordinate = business.coordinate
            if selection != target {
                skipSelectionCamera = true
                selection = target
            }
        case .place(let id):
            guard let point = app.realPlace(id: id)?.coordinate
                    ?? (app.destination?.id == id ? app.destination?.coordinate : nil) else { return }
            coordinate = point
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
            if let place = app.realPlace(id: id) {
                RealPlaceDetailCard(place: place) { selection = nil }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        case nil:
            EmptyView()
        }
    }

    /// Opens the ranked list of Off-Peak Quests (with score breakdowns), badged with the count.
    private var questsButton: some View {
        Button {
            showQuests = true
        } label: {
            Image(systemName: "flag.checkered")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.coral)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .overlay(alignment: .topTrailing) {
                    let count = app.offers.count
                    if count > 0 {
                        Text("\(count)")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(.white)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Theme.coralDeep, in: Circle())
                            .offset(x: 4, y: -4)
                    }
                }
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
        .padding(.leading, 12)
        .accessibilityLabel("Off-Peak Quests")
    }

    /// ✨ opens "Suggested for you" in a short sheet; the badge shows how many.
    private var suggestionsButton: some View {
        Button {
            app.refreshRecommendations()
            showSuggestions = true
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.sky)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .overlay(alignment: .topTrailing) {
                    let count = app.recommendations.items.count
                    if count > 0 {
                        Text("\(count)")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(.white)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Theme.sky, in: Circle())
                            .offset(x: 4, y: -4)
                    }
                }
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
        .padding(.leading, 12)
        .accessibilityLabel("Suggested for you")
    }

    private var legendButton: some View {
        Button {
            showLegend = true
        } label: {
            Image(systemName: "info.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.coral)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
        .padding(.leading, 12)
        .padding(.top, 8)
        .accessibilityLabel("Map legend")
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
