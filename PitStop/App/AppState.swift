import CoreLocation
import Observation

/// Composition root: owns every service and store, and is shared with views through the environment.
///
/// Data flow for location (the heart of the app):
///
///     LocationService (real GPS) ─┐
///                                 ├─► AppState.handleLocation ─► RunTracker
///     DemoRunSimulator (fake) ────┘                           ├► NavigationEngine (turn-by-turn)
///                                                             ├► PlacesService (refresh nearby places)
///                                                             └► evaluateOffers (quest banner)
///
/// While Demo Mode is playing, real GPS fixes are ignored so the two never mix.
///
/// Two kinds of businesses appear on the map:
/// - `partners`: businesses on PitStop. Only these can offer rewards, create quests, or be routed to.
/// - `places.places`: real MapKit places. Display-only, shown muted as "Not on PitStop yet".
@Observable
final class AppState {
    let location = LocationService()
    let places = PlacesService()
    let run = RunTracker()
    let businessStore = BusinessStore()
    let questStore = QuestStore()
    let planStore = RunPlanStore()
    let finder = DestinationFinder()
    let routeGenerator = RouteGenerator()
    let navigation = NavigationEngine()
    let developer = DeveloperSettings()
    let demo = DemoRunSimulator()
    let preferences = AppPreferences()
    let crossings = CrossingAlertEngine()
    let history = HistoryStore()
    let motion = MotionService()
    let antiCheat = AntiCheatEngine()
    let checkIn = CheckInMonitor()
    /// AI provider. Features talk to it through the `AIService` protocol, so it can be swapped.
    let ai = GeminiService()

    /// The location the app is using right now: real GPS, or simulated in Demo Mode.
    private(set) var currentLocation: CLLocation?

    /// The plan for the current run (nil = free run, or no run).
    private(set) var activePlan: RunPlan?
    /// A plan chosen on the sheet whose run hasn't started yet (destinations being picked).
    private(set) var pendingPlan: RunPlan?
    /// Where the current run is headed, if anywhere.
    private(set) var destination: PlannedDestination?
    /// Short note on how the destination was chosen (e.g. "Surprise pick").
    private(set) var destinationNote: String?

    /// Route options for the current destination (shown before the run starts).
    private(set) var routeOptions: [RouteOption] = []
    var selectedRouteID: RouteOption.ID?
    private(set) var isGeneratingRoutes = false
    /// The AI route agent's pick (shown as the "AI suggested" card), its progress, and any failure.
    private(set) var aiSuggestion: RouteAgent.Suggestion?
    private(set) var aiPlanningStep: String?
    private(set) var aiRouteError: AIError?
    /// Card vs. chips: "Show other options" switches to the chips.
    var showAISuggestion = true
    @ObservationIgnored private var aiTask: Task<Void, Never>?

    /// Where the run started (the finish line for out-and-back reroutes).
    @ObservationIgnored private var runStart: CLLocationCoordinate2D?
    @ObservationIgnored private var routeTask: Task<Void, Never>?
    private(set) var isRerouting = false

    /// IDs (business or real place) the AI recommender picked. Filled in by AI §5.
    var recommendedIDs: Set<String> = []
    /// IDs of places the user has run to and checked in at (from run history).
    var visitedIDs: Set<String> { history.visitedIDs }

    /// Shown as the celebration card after a check-in.
    var celebration: CheckInEvent?
    /// Badges unlocked by the run that just ended (celebrated after the check-in card).
    var badgeCelebration: [BadgeKind] = []
    /// The run that just ended (the finished card shows its verification).
    private(set) var lastFinishedRun: RunRecord?
    /// Developer "fake run at car speed": playback at 30 mph with no steps, to show anti-cheat rejecting it.
    private(set) var isFakeCarRun = false
    @ObservationIgnored private var runID = UUID().uuidString
    @ObservationIgnored private var runQuestID: Quest.ID?
    @ObservationIgnored private var checkedInDestination: PlannedDestination?

    /// The offer currently shown in the in-app banner.
    private(set) var bannerOffer: QuestOffer?
    /// Asks the map to fly to a pin (set on Accept and on a surprise pick).
    var mapFocus: MapSelection?

    /// Quests already announced (banner + notification), so each is announced once.
    @ObservationIgnored private var announcedQuestIDs: Set<Quest.ID> = []

    init() {
        location.onLocation = { [weak self] fix in
            guard let self else { return }
            // Demo playback owns the location while it runs.
            if self.demo.isPlaying { return }
            self.handleLocation(fix)
        }
        demo.onLocation = { [weak self] fix in
            self?.handleLocation(fix)
        }
        checkIn.onCheckIn = { [weak self] destination in
            self?.handleCheckIn(at: destination)
        }
        crossings.onAlert = { [weak self] point in
            guard let self, self.preferences.voiceCues else { return }
            SpeechService.shared.speak(oneOf: point.kind.voiceCues, key: "crossing.\(point.kind.rawValue)")
        }
    }

    // MARK: Location pipeline

    /// Single entry point for every location fix.
    func handleLocation(_ fix: CLLocation) {
        currentLocation = fix
        places.refreshIfNeeded(around: fix)
        run.ingest(fix)
        if run.state == .running {
            antiCheat.ingest(fix)
            checkIn.update(with: fix)
        }
        if run.state == .running, navigation.isNavigating {
            navigation.update(with: fix)
            if preferences.crossingAlerts { crossings.update(progress: navigation.progress) }
        }
        evaluateOffers()
    }

    // MARK: Partners (the ONLY input to quest matching and route generation)

    var partners: [Business] { businessStore.businesses }

    func partner(id: Business.ID) -> Business? {
        businessStore.business(id: id)
    }

    func saveBusiness(_ business: Business) {
        businessStore.upsert(business)
        questStore.updateReward(business.reward, for: business.id)
        evaluateOffers()
    }

    func deleteBusiness(id: Business.ID) {
        businessStore.delete(id: id)
        questStore.removeAll(for: id)
        if bannerOffer?.business.id == id { bannerOffer = nil }
    }

    /// Business mode's big switch. Going slow opens an Off-Peak Quest; un-slowing expires it.
    func setSlow(_ isSlow: Bool, businessID: Business.ID) {
        businessStore.setSlow(isSlow, id: businessID)
        if isSlow, let business = partner(id: businessID) {
            questStore.open(for: business)
        } else {
            questStore.expire(for: businessID)
            if bannerOffer?.business.id == businessID { bannerOffer = nil }
        }
        evaluateOffers()
    }

    // MARK: Quest offers

    /// All quests this runner could take right now, best first. Dismissed ones are hidden.
    var offers: [QuestOffer] {
        guard let here = currentLocation else { return [] }
        return QuestMatcher.offers(
            quests: questStore.quests.filter { !questStore.dismissedIDs.contains($0.id) },
            businesses: partners,
            runner: here,
            plannedDestination: destination?.location,
            recentVisits: questStore.recentVisits(to:)
        )
    }

    var acceptedQuest: (quest: Quest, business: Business)? {
        guard let quest = questStore.acceptedQuest, let business = partner(id: quest.businessId) else { return nil }
        return (quest, business)
    }

    /// Announces the best new offer: in-app banner, haptic, and a local notification.
    func evaluateOffers() {
        // Drop a banner whose quest is no longer offerable.
        if let shown = bannerOffer, !offers.contains(where: { $0.id == shown.id }) {
            bannerOffer = nil
        }
        guard bannerOffer == nil, acceptedQuest == nil,
              let next = offers.first(where: { !announcedQuestIDs.contains($0.id) }) else { return }
        announcedQuestIDs.insert(next.id)
        bannerOffer = next
        Haptics.success()
        NotificationService.notifyQuestOffer(next)
    }

    func accept(_ offer: QuestOffer) {
        questStore.accept(offer.quest.id)
        bannerOffer = nil
        setDestination(PlannedDestination(business: offer.business), note: "Off-Peak Quest")
        mapFocus = .partner(offer.business.id)
        Haptics.tap()
        // Accepted mid-run: check in there instead, and reroute through the business right away.
        if run.isActive {
            checkIn.start(target: PlannedDestination(business: offer.business))
            reroute(viaDestination: true)
        }
    }

    func dismiss(_ offer: QuestOffer) {
        questStore.dismiss(offer.quest.id)
        bannerOffer = nil
        evaluateOffers()
    }

    func cancelAcceptedQuest() {
        if let accepted = acceptedQuest, destination?.id == accepted.business.id {
            clearDestination()
        }
        questStore.cancelAccepted()
    }

    // MARK: Destination

    func setDestination(_ destination: PlannedDestination, note: String? = nil) {
        self.destination = destination
        destinationNote = note
        if !run.isActive { generateRoutes() }
    }

    func clearDestination() {
        destination = nil
        destinationNote = nil
        routeTask?.cancel()
        routeOptions = []
        selectedRouteID = nil
        isGeneratingRoutes = false
        resetAIRoute()
        if !navigation.isNavigating { crossings.reset() }
    }

    // MARK: Routes

    var selectedRoute: RouteOption? {
        routeOptions.first { $0.id == selectedRouteID } ?? routeOptions.first
    }

    /// The plan that routes are built for: the pending one, or the last-used defaults.
    var planForRouting: RunPlan { pendingPlan ?? planStore.lastPlan }

    /// Builds 2–3 route options from here to the destination that fit the plan's goal.
    func generateRoutes() {
        guard let here = currentLocation?.coordinate, let destination else { return }
        let plan = planForRouting
        let request = RouteGenerator.Request(start: here, destination: destination.coordinate,
                                             destinationName: destination.name,
                                             target: targetDistance(for: plan), shape: plan.shape,
                                             transport: plan.activity.transportType)
        routeTask?.cancel()
        routeOptions = []
        selectedRouteID = nil
        isGeneratingRoutes = true
        resetAIRoute()
        routeTask = Task {
            let options = await routeGenerator.options(for: request)
            guard !Task.isCancelled else { return }
            routeOptions = options
            selectedRouteID = options.first?.id
            isGeneratingRoutes = false
            prepareCrossings()
            // The standard routes are ready (and are the fallback), so now let the AI try for a nicer one.
            planAIRoute(request: request, plan: plan, baseline: options.first)
        }
    }

    // MARK: AI route agent

    private func resetAIRoute() {
        aiTask?.cancel()
        aiSuggestion = nil
        aiPlanningStep = nil
        aiRouteError = nil
        showAISuggestion = true
    }

    /// Asks the route agent for a scenic route. On success it's inserted first and selected;
    /// on any failure the RouteGenerator's options stay as they are, with a small "AI unavailable" note.
    private func planAIRoute(request: RouteGenerator.Request, plan: RunPlan, baseline: RouteOption?) {
        guard preferences.aiRouteSuggestions else { return }
        guard ai.isAvailable else {
            aiRouteError = ai.connection == .unavailable ? .notConfigured : (ai.lastError ?? .rateLimited(retryAfter: nil))
            return
        }
        let destinationID = destination?.id
        let context = RouteAgent.Context(request: request, plan: plan,
                                         interests: Array(preferences.interests).sorted { $0.rawValue < $1.rawValue },
                                         secondsPerMeter: planStore.pace(for: plan.activity).secondsPerMeter,
                                         baseline: baseline)
        aiPlanningStep = "Planning a scenic route…"
        aiTask = Task {
            do {
                let suggestion = try await RouteAgent(ai: ai, generator: routeGenerator)
                    .suggest(context) { step in self.aiPlanningStep = step }
                // Ignore late answers if the user moved on.
                guard !Task.isCancelled, destination?.id == destinationID, !run.isActive else { return }
                routeOptions.insert(suggestion.option, at: 0)
                aiSuggestion = suggestion
                showAISuggestion = true
                selectRoute(suggestion.option.id)
                Haptics.success()
            } catch {
                guard !Task.isCancelled else { return }
                aiRouteError = error as? AIError ?? .invalidResponse
            }
            aiPlanningStep = nil
        }
    }

    func selectRoute(_ id: RouteOption.ID) {
        selectedRouteID = id
        prepareCrossings()
    }

    /// Fetch crossing data for the selected (or active) route ahead of time, so alerts are ready.
    func prepareCrossings() {
        guard preferences.crossingAlerts, let route = navigation.route ?? selectedRoute else { return }
        crossings.prepare(route)
    }

    /// Off route: build a new route from here to the rest of the plan and keep navigating.
    /// - Parameter viaDestination: force the route through the destination (e.g. a quest accepted mid-run).
    func reroute(viaDestination: Bool = false) {
        guard let here = currentLocation?.coordinate, !isRerouting else { return }
        let plan = activePlan ?? planForRouting
        let stillHeadingOut = viaDestination || !navigation.reachedDestination || !navigation.isNavigating
        let finish = plan.shape == .outAndBack ? runStart : nil
        let via = stillHeadingOut ? destination?.coordinate : nil
        isRerouting = true
        Task {
            if let option = await routeGenerator.reroute(from: here, via: via, to: finish,
                                                         destinationName: destination?.name ?? "your destination",
                                                         transport: plan.activity.transportType) {
                navigation.start(option)
                prepareCrossings()
                if let arrival = option.destinationArrival {
                    checkIn.arrivalPoint = CLLocation(latitude: arrival.latitude, longitude: arrival.longitude)
                }
                if demo.isPlaying || developer.demoMode || isFakeCarRun { startDemoPlayback(along: option, plan: plan) }
            }
            isRerouting = false
        }
    }

    private func startDemoPlayback(along route: RouteOption, plan: RunPlan) {
        if isFakeCarRun {
            // 13.4 m/s = 30 mph at real time: obviously a car.
            demo.start(along: route.coordinates, metersPerSecond: 13.4, multiplier: 1,
                       dwellAt: route.destinationDistance)
            return
        }
        let metersPerSecond = 1 / planStore.pace(for: plan.activity).secondsPerMeter
        demo.start(along: route.coordinates, metersPerSecond: metersPerSecond, multiplier: developer.demoSpeed,
                   dwellAt: route.destinationDistance)
    }

    /// Developer button: play the selected route at car speed so anti-cheat rejects it, live.
    func startFakeCarRun() {
        guard destination != nil, selectedRoute != nil else { return }
        isFakeCarRun = true
        startRun(with: planForRouting)
    }

    // MARK: Check-in

    /// Runner stayed 10 s at the destination: verify, unlock the partner reward, celebrate.
    private func handleCheckIn(at place: PlannedDestination) {
        checkedInDestination = place
        let verification = currentVerification()
        let isFirstVisit = !history.visitedIDs.contains(place.id)

        var unlocked: String?
        var locked: String?
        if place.isPartner, let accepted = acceptedQuest, accepted.business.id == place.id {
            runQuestID = accepted.quest.id
            if verification.passed {
                questStore.complete(accepted.quest.id)
                history.saveReward(EarnedReward(business: place, reward: accepted.quest.reward,
                                                questId: accepted.quest.id, runId: runID))
                unlocked = accepted.quest.reward
            } else {
                locked = accepted.quest.reward
            }
        }
        // Passport stamp: first VERIFIED check-in at this place.
        var earnedStamp = false
        if verification.passed, !history.hasStamp(for: place.id) {
            history.saveStamp(Stamp(place: place, runId: runID))
            earnedStamp = true
        }
        celebration = CheckInEvent(destination: place, reward: unlocked, lockedReward: locked,
                                   verification: verification, isFirstVisit: isFirstVisit, earnedStamp: earnedStamp)
        verification.passed ? Haptics.success() : Haptics.error()
    }

    /// Anti-cheat verdict for the run so far.
    func currentVerification() -> VerificationResult {
        antiCheat.evaluate(distance: run.distanceMeters, duration: run.elapsed(),
                           pedometerSteps: motion.steps, motionDenied: motion.isDenied,
                           enabled: developer.antiCheatEnabled)
    }

    /// Target distance (meters) for a plan, using the user's pace for time goals.
    func targetDistance(for plan: RunPlan) -> Double {
        plan.targetDistance(secondsPerMeter: planStore.pace(for: plan.activity).secondsPerMeter)
    }

    // MARK: Planning (Plan sheet → find destinations → choose → start)

    /// Starts the goal-matched destination search for a plan. The plan stays pending until the run starts.
    func findDestinations(for plan: RunPlan) {
        planStore.save(plan)
        pendingPlan = plan
        guard let here = currentLocation else { return }
        finder.find(plan: plan, target: targetDistance(for: plan), from: here,
                    partners: partners,
                    openQuest: { [questStore] id in questStore.openQuest(for: id) },
                    nearbyPlaces: places.places)
    }

    /// Picks one destination from the results. Choosing a partner with a live quest accepts the quest.
    func choose(_ match: DestinationMatch, note: String? = nil) {
        if let questID = match.questID {
            questStore.accept(questID)
            bannerOffer = nil
        }
        setDestination(match.destination, note: note ?? (match.hasQuest ? "Off-Peak Quest" : "Fits your goal"))
        mapFocus = match.destination.isPartner ? .partner(match.id) : .place(match.id)
    }

    /// "Surprise me": random pick from the best few (quests first, since they sort to the top).
    func surpriseMatch() -> DestinationMatch? {
        finder.matches.prefix(3).randomElement()
    }

    /// Start button once a plan is pending.
    func startPlannedRun() {
        startRun(with: planForRouting)
    }

    func cancelPlan() {
        pendingPlan = nil
        finder.reset()
    }

    /// Looks up a real place by id in the nearby cache or in the destination results
    /// (ring searches can find places outside the nearby cache).
    func realPlace(id: RealPlace.ID) -> RealPlace? {
        places.place(id: id) ?? finder.match(id: id)?.realPlace
    }

    // MARK: Map presentation

    /// Direction the user faces: GPS course while moving (also what Demo Mode produces), compass otherwise.
    var userHeading: Double? {
        if let fix = currentLocation, fix.course >= 0, fix.speed > 1 { return fix.course }
        return location.heading
    }

    func pinStatus(for business: Business, selected: Bool) -> PinStatus {
        PinStatus(isSelected: selected,
                  hasQuest: business.isSlow && questStore.openQuest(for: business.id) != nil,
                  isNew: business.isNew,
                  isRecommended: recommendedIDs.contains(business.id),
                  isVisited: visitedIDs.contains(business.id),
                  isDestination: destination?.id == business.id,
                  matchLabel: matchLabel(for: business.id))
    }

    func pinStatus(for place: RealPlace, selected: Bool) -> PinStatus {
        PinStatus(isSelected: selected,
                  isRecommended: recommendedIDs.contains(place.id),
                  isVisited: visitedIDs.contains(place.id),
                  isDestination: destination?.id == place.id,
                  matchLabel: matchLabel(for: place.id))
    }

    /// "2.9 mi · 96%" under pins that are goal-matched destinations.
    func matchLabel(for id: String) -> String? {
        guard let match = finder.match(id: id) else { return nil }
        return "\(Format.distance(match.totalDistance)) · \(Int((match.fit * 100).rounded()))%"
    }

    // MARK: Places

    func refreshNearbyPlaces() {
        guard let here = currentLocation else { return }
        places.forceRefresh(around: here)
    }

    // MARK: Run controls

    /// Starts a run with a plan. The plan is saved as next time's default.
    func startRun(with plan: RunPlan) {
        planStore.save(plan)
        activePlan = plan
        pendingPlan = nil
        finder.reset()   // results leave the map once the run starts; the destination stays
        runStart = currentLocation?.coordinate
        // With a chosen route, the goal is that route's real length.
        let route = destination == nil ? nil : selectedRoute
        run.start(targetDistance: route?.distance ?? targetDistance(for: plan))

        // Anti-cheat and check-in. Demo playback is time-compressed ×N and has no real steps,
        // so it gets normalized speeds and synthetic steps (none at all for the fake car run).
        runID = UUID().uuidString
        runQuestID = nil
        checkedInDestination = nil
        lastFinishedRun = nil
        let playback = route != nil && (developer.demoMode || isFakeCarRun)
        // Realistic synthetic steps: ~1.15 steps/m running (≈185 spm at 10:00/mi), ~1.4 walking.
        let stepsPerMeter: Double? = playback
            ? (isFakeCarRun || plan.activity == .bike ? 0 : (plan.activity == .walk ? 1.4 : 1.15))
            : nil
        antiCheat.start(activity: plan.activity,
                        timeScale: playback && !isFakeCarRun ? developer.demoSpeed : 1,
                        syntheticStepsPerMeter: stepsPerMeter)
        if !playback { motion.start() }
        checkIn.start(target: destination, arrival: route?.destinationArrival)

        if let route {
            navigation.start(route)
            prepareCrossings()   // no-op if already fetched while the route was selected
            routeOptions = []
            if playback { startDemoPlayback(along: route, plan: plan) }
        }
        location.setBackgroundTracking(true)
        // Ask for permissions at the moment they matter: when a run actually starts.
        if location.authorization == .authorizedWhenInUse {
            location.requestAlways()
        }
        NotificationService.requestAuthorizationIfNeeded()
    }

    func pauseRun() {
        run.pause()
        demo.pause()
    }

    func resumeRun() {
        run.resume()
        demo.resume()
    }

    func endRun() {
        run.end()
        demo.stop()
        navigation.stop()
        crossings.reset()
        motion.stop()
        checkIn.stop()
        location.setBackgroundTracking(false)

        let verification = currentVerification()
        // Only real, verified runs teach the app your pace.
        if let plan = activePlan, let pace = run.averagePace, verification.passed, !demo.isPlaying, !developer.demoMode {
            planStore.recordPace(pace, distance: run.distanceMeters, activity: plan.activity)
        }

        let record = RunRecord(id: runID, date: run.startDate ?? .now, plan: activePlan, destination: destination,
                               checkedIn: checkedInDestination != nil, questId: runQuestID,
                               distanceMeters: run.distanceMeters, durationSeconds: run.elapsed(),
                               averagePace: run.averagePace, route: thinnedTrace(), verification: verification)
        // Skip accidental Start → End taps.
        if run.distanceMeters > 20 || checkedInDestination != nil {
            history.save(record)
            // Milestone badges are re-checked against the full verified history.
            if verification.passed {
                let fresh = history.awardNewBadges()
                if !fresh.isEmpty {
                    badgeCelebration = fresh
                    Haptics.success()
                }
            }
        }
        lastFinishedRun = record
    }

    /// The GPS trace with points at least 5 m apart (smaller to store, same shape on a map).
    private func thinnedTrace() -> [GeoPoint] {
        var result: [GeoPoint] = []
        var last: CLLocation?
        for fix in run.trace where last == nil || fix.distance(from: last!) >= 5 {
            result.append(GeoPoint(fix.coordinate))
            last = fix
        }
        return result
    }

    /// "Done" on the finished-run card.
    func resetRun() {
        run.reset()
        activePlan = nil
        lastFinishedRun = nil
        isFakeCarRun = false
        if acceptedQuest == nil { clearDestination() }
    }

    // MARK: Future Places

    func toggleSaved(_ destination: PlannedDestination, source: SavedPlace.Source = .map) {
        if history.isSaved(destination.id) {
            history.removeSavedPlace(id: destination.id)
        } else {
            history.savePlace(destination, source: source)
            Haptics.success()
        }
    }

    /// "Plan a run here" from My Places: make it the destination and build routes for the last plan.
    func planRun(to destination: PlannedDestination) {
        cancelPlan()
        setDestination(destination, note: "From My Places")
        mapFocus = destination.isPartner ? .partner(destination.id) : .place(destination.id)
    }
}
