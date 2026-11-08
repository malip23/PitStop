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
    let auth = AuthService()
    @ObservationIgnored let liveActivity = LiveActivityManager()
    @ObservationIgnored private var lastActivityStep: String?
    /// Admin/business accounts can preview the runner tabs on one phone (local only; Firestore role unchanged).
    var previewAsRunner = false

    /// The signed-in user's role from Firestore (`users/{uid}.role`).
    var role: UserRole {
        previewAsRunner ? .runner : (auth.profile?.role ?? .runner)
    }
    let recommendations = RecommendationEngine()
    let suggestions = InterestSuggestionEngine()
    let narration = NarrationEngine()
    @ObservationIgnored private var isPickingSuggestion = false

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

    /// IDs (business or real place) the recommender picked. Drives the ⭐ pins on the map.
    var recommendedIDs: Set<String> { Set(recommendations.items.map(\.id)) }
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

    /// The single popup slot (safety > offers > suggestions > narration).
    let popups = PopupManager()
    /// Which tab is showing (popups dock on the map when it's the Run tab).
    var selectedTab: AppTab = .run

    /// Timed offers: when each visible offer runs out, and offers that expired this run (never re-shown).
    private(set) var offerDeadlines: [Quest.ID: Date] = [:]
    private(set) var expiredOfferIDs: Set<Quest.ID> = []
    @ObservationIgnored private var offerTimers: [Quest.ID: Task<Void, Never>] = [:]
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
        auth.onUserChange = { [weak self] uid in self?.userChanged(uid) }
        auth.onProfileChange = { [weak self] profile in
            // One-time upload of old local mock businesses (only business/admin accounts may create them).
            if profile?.role.canManageBusinesses == true { self?.businessStore.migrateLocalFileIfNeeded() }
        }
        businessStore.onChange = { [weak self] in self?.remoteDataChanged() }
        questStore.onChange = { [weak self] in self?.remoteDataChanged() }
        popups.onPresent = { [weak self] popup in
            self?.popupPresented(popup)
        }
        checkIn.onCheckIn = { [weak self] destination in
            self?.handleCheckIn(at: destination)
        }
        crossings.onAlert = { [weak self] point in
            guard let self else { return }
            // Safety is the top priority: it pre-empts any other popup (and cuts off narration speech).
            self.popups.show(.safety(point), id: "safety-\(point.id)", autoDismissAfter: 12)
            if self.preferences.voiceCues {
                SpeechService.shared.stop()
                SpeechService.shared.speak(oneOf: point.kind.voiceCues, key: "crossing.\(point.kind.rawValue)")
            }
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
            if preferences.crossingAlerts {
                crossings.update(progress: navigation.progress)
                // The crossing is behind the runner: close its pill.
                if crossings.activeAlert == nil { popups.remove { if case .safety = $0.content { true } else { false } } }
            }
            checkInterestSuggestions()
            checkNarration()
            reportQuestETA()
        }
        if run.state == .running {
            // A new turn instruction is sent right away; everything else is throttled.
            let step = navigation.nextStep?.instruction
            refreshLiveActivity(urgent: step != lastActivityStep)
            lastActivityStep = step
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
        endOffers(for: id, businessName: partner(id: id)?.name)
        // Quests first: firestore.rules checks quest deletes against the business's owner,
        // which it can't do once the business document is gone.
        questStore.removeAll(for: id)
        businessStore.delete(id: id)
    }

    /// Business mode's big switch. Going slow opens an Off-Peak Quest; un-slowing expires it.
    func setSlow(_ isSlow: Bool, businessID: Business.ID) {
        businessStore.setSlow(isSlow, id: businessID)
        if isSlow, let business = partner(id: businessID) {
            questStore.open(for: business)
        } else {
            endOffers(for: businessID, businessName: partner(id: businessID)?.name)
            questStore.expire(for: businessID)
        }
        evaluateOffers()
    }

    // MARK: Quest offers

    /// All quests this runner could take right now, best first. Dismissed ones are hidden.
    var offers: [QuestOffer] {
        guard let here = currentLocation else { return [] }
        return QuestMatcher.offers(
            quests: questStore.quests.filter { !questStore.dismissedIDs.contains($0.id) && !expiredOfferIDs.contains($0.id) },
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

    /// The offer popup currently visible, if any.
    var visibleOffer: QuestOffer? {
        if case .offer(let offer) = popups.current?.content { return offer }
        return nil
    }

    private static func offerPopupID(_ offer: QuestOffer) -> String { "offer-\(offer.quest.id)" }

    // MARK: Timed offers

    /// An offer popup just became visible: start its countdown (once; it keeps running if a safety
    /// alert interrupts it), tell the business it was shown, and announce it for VoiceOver.
    private func popupPresented(_ popup: PopupManager.Popup) {
        // Narration is spoken only when it actually appears (never while waiting behind other popups).
        if case .narration(let line) = popup.content {
            if preferences.narrationVoice && preferences.voiceCues {
                SpeechService.shared.speak(line.text, style: .narration)
            }
            VoiceOver.announce(line.text)
            return
        }
        guard case .offer(let offer) = popup.content, offerDeadlines[offer.quest.id] == nil else { return }
        defer { refreshLiveActivity(urgent: true) }   // show the offer + countdown on the Lock Screen
        let id = offer.quest.id
        offerDeadlines[id] = .now.addingTimeInterval(OfferTiming.countdown)
        questStore.recordOffer(.shown, for: id)
        VoiceOver.announce("Off-Peak Quest: \(offer.quest.reward) at \(offer.business.name). \(Int(OfferTiming.countdown)) seconds to accept.")

        offerTimers[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(OfferTiming.countdown - OfferTiming.warningAt))
            guard !Task.isCancelled, let self else { return }
            if case .offer(let shown) = self.popups.current?.content, shown.quest.id == id {
                Haptics.light()
                VoiceOver.announce("\(Int(OfferTiming.warningAt)) seconds left to accept.")
            }
            try? await Task.sleep(for: .seconds(OfferTiming.warningAt))
            guard !Task.isCancelled else { return }
            self.expireOffer(offer)
        }
    }

    /// Time's up: the popup animates away and the offer won't come back this run.
    private func expireOffer(_ offer: QuestOffer) {
        let id = offer.quest.id
        stopOfferTimer(id)
        expiredOfferIDs.insert(id)
        questStore.recordOffer(.expired, for: id)
        popups.dismiss(id: Self.offerPopupID(offer))
        VoiceOver.announce("Offer expired.")
    }

    private func stopOfferTimer(_ id: Quest.ID) {
        offerTimers[id]?.cancel()
        offerTimers[id] = nil
        // The offer just closed (accepted, passed, expired, or ended): clear it from the Live Activity.
        Task { @MainActor in self.refreshLiveActivity(urgent: true) }
    }

    // MARK: Live Activity

    /// Current run data for the Lock Screen / Dynamic Island.
    func liveActivityState() -> RunActivityAttributes.ContentState {
        let elapsed = run.elapsed()
        let left: Double? = navigation.isNavigating
            ? navigation.remainingDistance
            : run.targetDistance.map { max(0, $0 - run.distanceMeters) }
        var offer: RunActivityAttributes.ContentState.Offer?
        if let visible = visibleOffer, let deadline = offerDeadlines[visible.quest.id] {
            offer = .init(businessName: visible.business.name, reward: visible.quest.reward, deadline: deadline)
        }
        return .init(timerStart: Date.now.addingTimeInterval(-elapsed),
                     isPaused: run.state == .paused,
                     pausedElapsed: elapsed,
                     distanceText: Format.distance(run.distanceMeters),
                     paceText: "\(Format.pace(secondsPerMeter: run.currentPace)) \(Format.paceUnit)",
                     leftText: left.map { Format.distance($0) },
                     nextInstruction: navigation.isNavigating ? (navigation.nextStep?.instruction ?? "Continue on route") : nil,
                     nextSymbol: navigation.isNavigating ? (navigation.nextStep?.symbol ?? "arrow.up") : nil,
                     nextDistanceText: navigation.isNavigating ? Format.shortDistance(navigation.distanceToNextStep) : nil,
                     offer: offer)
    }

    func refreshLiveActivity(urgent: Bool = false) {
        guard run.isActive else { return }
        liveActivity.update(liveActivityState(), urgent: urgent)
    }

    func offerDeadline(for questID: Quest.ID) -> Date? { offerDeadlines[questID] }

    /// The business ended its promotion: close its offer, with a short "Offer ended" note if it was visible.
    private func endOffers(for businessID: Business.ID, businessName: String?) {
        if let visible = visibleOffer, visible.business.id == businessID {
            stopOfferTimer(visible.quest.id)
            popups.dismiss(id: Self.offerPopupID(visible))
            popups.show(.info(.init(title: "Offer ended", message: "\(businessName ?? "The business") is busy again. Maybe next time!",
                                    symbol: "clock.badge.xmark")),
                        id: "ended-\(visible.quest.id)", autoDismissAfter: 3)
            VoiceOver.announce("Offer ended.")
        }
        removeOfferPopups(for: businessID)
    }

    private func removeOfferPopups(for businessID: Business.ID) {
        popups.remove { if case .offer(let o) = $0.content { o.business.id == businessID } else { false } }
    }

    /// Announces the best new offer through the popup queue (plus haptic and a local notification).
    /// Runners only; one offer queued at a time.
    func evaluateOffers() {
        // Drop offer popups whose quest is no longer offerable.
        let live = Set(offers.map(\.id))
        popups.remove { if case .offer(let o) = $0.content { !live.contains(o.id) } else { false } }

        let offerQueued = popups.contains { if case .offer = $0.content { true } else { false } }
        guard role == .runner, !offerQueued, acceptedQuest == nil,
              let next = offers.first(where: { !announcedQuestIDs.contains($0.id) }) else { return }
        announcedQuestIDs.insert(next.id)
        popups.show(.offer(next), id: Self.offerPopupID(next))
        Haptics.success()
        NotificationService.notifyQuestOffer(next)
    }

    func accept(_ offer: QuestOffer) {
        stopOfferTimer(offer.quest.id)
        questStore.recordOffer(.accepted, for: offer.quest.id)
        questStore.accept(offer.quest.id)
        popups.dismiss(id: Self.offerPopupID(offer))
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
        stopOfferTimer(offer.quest.id)
        questStore.recordOffer(.dismissed, for: offer.quest.id)
        questStore.dismiss(offer.quest.id)
        popups.dismiss(id: Self.offerPopupID(offer))
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
                suggestions.routeChanged(option)
                narration.routeChanged(option)
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
        // Tell the business about the visit (verdict only: no health data, no route).
        if place.isPartner, let uid = auth.uid {
            Visit.record(businessId: place.id, runnerUid: uid, questId: runQuestID, verification: verification)
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
            removeOfferPopups(for: match.destination.id)
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
        places.place(id: id) ?? finder.match(id: id)?.realPlace ?? recommendations.recommendation(id: id)?.realPlace
    }

    // MARK: Recommendations

    /// Refreshes "Suggested for you" when stale (3 h), after a new visit, or when forced.
    func refreshRecommendations(force: Bool = false) {
        guard let here = currentLocation else { return }
        let plan = planStore.lastPlan
        let context = RecommendationEngine.Context(
            here: here, partners: partners,
            liveQuestReward: { [questStore, businessStore] id in
                guard businessStore.business(id: id)?.isSlow == true,
                      let quest = questStore.openQuest(for: id), quest.status == .active else { return nil }
                return quest.reward
            },
            nearbyPlaces: places.places, runs: history.runs(),
            saved: history.savedPlaces(), interests: preferences.interests,
            plan: plan, target: targetDistance(for: plan))
        if force { recommendations.refresh(context, ai: ai) } else { recommendations.refreshIfNeeded(context, ai: ai) }
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
            if preferences.narration {
                narration.prepare(route: route, interests: preferences.interests, partners: partners,
                                  nearbyPlaces: places.places, ai: ai, demoMode: playback)
            }
            if preferences.runSuggestions {
                suggestions.prepare(route: route, interests: preferences.interests, partners: partners,
                                    hasLivePromotion: { [questStore, businessStore] id in
                                        businessStore.business(id: id)?.isSlow == true && questStore.openQuest(for: id) != nil
                                    },
                                    nearbyPlaces: places.places, excludeID: destination?.id, demoMode: playback)
            }
        }
        location.setBackgroundTracking(true)
        lastActivityStep = nil
        liveActivity.start(destinationName: destination?.name, activitySymbol: plan.activity.symbol,
                           state: liveActivityState())
        // Ask for permissions at the moment they matter: when a run actually starts.
        if location.authorization == .authorizedWhenInUse {
            location.requestAlways()
        }
        NotificationService.requestAuthorizationIfNeeded()
    }

    func pauseRun() {
        run.pause()
        demo.pause()
        refreshLiveActivity(urgent: true)
    }

    func resumeRun() {
        run.resume()
        demo.resume()
        refreshLiveActivity(urgent: true)
    }

    func endRun() {
        // Leave the final stats on the Lock Screen for a moment.
        var final = liveActivityState()
        final.isPaused = true
        final.offer = nil
        final.nextInstruction = nil
        liveActivity.end(finalState: final)
        run.end()
        demo.stop()
        navigation.stop()
        crossings.reset()
        suggestions.reset()
        narration.reset()
        popups.remove {
            switch $0.content {
            case .suggestion, .narration: true
            default: false
            }
        }
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
        expiredOfferIDs = []   // "expired for this run": a new run may offer it again
        offerDeadlines = [:]
        if acceptedQuest == nil { clearDestination() }
    }

    // MARK: Accounts and live sync

    /// Sign-in starts the live Firestore listeners and the history merge; sign-out stops them.
    private func userChanged(_ uid: String?) {
        previewAsRunner = false
        if let uid {
            businessStore.start(uid: uid)
            questStore.start(uid: uid)
            Task { await history.attach(uid: uid) }
        } else {
            if run.isActive { endRun() }
            resetRun()
            businessStore.stop()
            questStore.stop()
            history.detach()
            popups.remove { _ in true }
            announcedQuestIDs = []
        }
    }

    /// A business or quest changed (possibly on another phone): re-check offers, and if the business
    /// behind the visible offer stopped its promotion, close it with "Offer ended".
    private func remoteDataChanged() {
        if let visible = visibleOffer {
            let business = partner(id: visible.business.id)
            let quest = questStore.quests.first { $0.id == visible.quest.id }
            if business?.isSlow != true || quest?.status != .active {
                endOffers(for: visible.business.id, businessName: business?.name ?? visible.business.name)
            }
        }
        evaluateOffers()
    }

    /// While heading to an accepted quest, send a live ETA (every 15 s) for the business dashboard.
    @ObservationIgnored private var lastETAReport: Date = .distantPast
    private func reportQuestETA() {
        guard let accepted = acceptedQuest, destination?.id == accepted.business.id,
              let route = navigation.route, !navigation.reachedDestination,
              Date.now.timeIntervalSince(lastETAReport) >= 15 else { return }
        lastETAReport = .now
        let remaining = max(0, route.destinationDistance - navigation.progress)
        // Live pace already reflects Demo playback speed; the plan's usual pace needs scaling.
        let timeScale = (demo.isPlaying && !isFakeCarRun) ? developer.demoSpeed : 1
        let pace = run.currentPace
            ?? planStore.pace(for: (activePlan ?? planForRouting).activity).secondsPerMeter / timeScale
        questStore.updateETA(remaining * pace, for: accepted.quest.id)
    }

    // MARK: Quick-stop suggestions (interest matches along the route)

    /// Called on every navigating fix. Removes suggestions the runner has passed, then (at most one
    /// at a time, respecting the 3-minute cooldown) asks the writer to pick and phrase the next one.
    private func checkInterestSuggestions() {
        let progress = navigation.progress
        popups.remove { if case .suggestion(let s) = $0.content { progress > s.alongRoute + 15 } else { false } }
        guard preferences.runSuggestions, role == .runner, run.state == .running, !isPickingSuggestion,
              !popups.contains(where: { if case .suggestion = $0.content { true } else { false } }) else { return }

        let timeScale = (demo.isPlaying && !isFakeCarRun) ? developer.demoSpeed : 1
        let eligible = suggestions.eligible(progress: progress, timeScale: timeScale)
        guard !eligible.isEmpty else { return }

        isPickingSuggestion = true
        Task {
            let pick = await SuggestionWriter.pick(from: eligible, progress: progress,
                                                   interests: preferences.interests, ai: ai)
            isPickingSuggestion = false
            guard let pick, run.state == .running, navigation.progress < pick.alongRoute else { return }
            suggestions.markSuggested(pick.id)
            popups.show(.suggestion(pick), id: "suggest-\(pick.id)", expiresIn: 120)
            Haptics.light()
            VoiceOver.announce(pick.message)
        }
    }

    // MARK: City-guide narration

    /// Queues the next narration when one is due. Lowest popup priority; waits up to 30 s behind
    /// other popups, then is dropped (the place has been passed by then).
    private func checkNarration() {
        guard preferences.narration, role == .runner, run.state == .running else { return }
        let timeScale = (demo.isPlaying && !isFakeCarRun) ? developer.demoSpeed : 1
        guard let line = narration.due(progress: navigation.progress, timeScale: timeScale) else { return }
        popups.show(.narration(line), id: "narration-\(line.id)", expiresIn: 30,
                    autoDismissAfter: line.destination == nil ? 10 : 15)
    }

    /// "Add stop": route through the place, then carry on with the rest of the plan.
    func addStop(_ suggestion: InterestSuggestion) {
        popups.dismiss(id: "suggest-\(suggestion.id)")
        guard let here = currentLocation?.coordinate, !isRerouting else { return }
        let plan = activePlan ?? planForRouting
        let headingOut = navigation.isNavigating && !navigation.reachedDestination && destination != nil
        var points = [here, suggestion.destination.coordinate]
        if headingOut, let destination { points.append(destination.coordinate) }
        if plan.shape == .outAndBack, let runStart { points.append(runStart) }
        let destinationLeg = headingOut ? 1 : 0
        let name = headingOut ? (destination?.name ?? suggestion.destination.name) : suggestion.destination.name

        isRerouting = true
        Haptics.success()
        Task {
            if let option = await routeGenerator.route(through: points, transport: plan.activity.transportType,
                                                       title: "With stop", kind: .reroute,
                                                       waypoints: [suggestion.destination.coordinate],
                                                       destinationLegIndex: destinationLeg, destinationName: name) {
                navigation.start(option)
                prepareCrossings()
                suggestions.routeChanged(option)
                narration.routeChanged(option)
                if headingOut, let arrival = option.destinationArrival {
                    checkIn.arrivalPoint = CLLocation(latitude: arrival.latitude, longitude: arrival.longitude)
                }
                if demo.isPlaying || developer.demoMode || isFakeCarRun { startDemoPlayback(along: option, plan: plan) }
            }
            isRerouting = false
        }
    }

    func saveSuggestion(_ suggestion: InterestSuggestion) {
        history.savePlace(suggestion.destination, source: .runSuggestion)
        Haptics.success()
        popups.dismiss(id: "suggest-\(suggestion.id)")
    }

    func dismissSuggestion(_ suggestion: InterestSuggestion) {
        popups.dismiss(id: "suggest-\(suggestion.id)")
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
