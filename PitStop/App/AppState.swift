import CoreLocation
import Observation

/// Composition root: owns every service and store, and is shared with views through the environment.
///
/// Data flow for location (the heart of the app):
///
///     LocationService (real GPS) ─┐
///                                 ├─► AppState.handleLocation ─► RunTracker
///     DemoRunSimulator (fake) ────┘                           ├► PlacesService (refresh nearby places)
///                                                             └► evaluateOffers (quest banner)
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

    /// The location the app is using right now: real GPS, or simulated in Demo Mode.
    private(set) var currentLocation: CLLocation?

    /// The plan for the current run (nil = free run, or no run).
    private(set) var activePlan: RunPlan?
    /// Where the current run is headed, if anywhere.
    private(set) var destination: PlannedDestination?
    /// Short note on how the destination was chosen (e.g. "Surprise pick").
    private(set) var destinationNote: String?

    /// The offer currently shown in the in-app banner.
    private(set) var bannerOffer: QuestOffer?
    /// Asks the map to fly to a pin (set on Accept and on a surprise pick).
    var mapFocus: MapSelection?

    /// Quests already announced (banner + notification), so each is announced once.
    @ObservationIgnored private var announcedQuestIDs: Set<Quest.ID> = []

    init() {
        location.onLocation = { [weak self] fix in
            self?.handleLocation(fix)
        }
    }

    // MARK: Location pipeline

    /// Single entry point for every location fix.
    func handleLocation(_ fix: CLLocation) {
        currentLocation = fix
        places.refreshIfNeeded(around: fix)
        run.ingest(fix)
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
    }

    func clearDestination() {
        destination = nil
        destinationNote = nil
    }

    /// Target distance (meters) for a plan, using the user's pace for time goals.
    func targetDistance(for plan: RunPlan) -> Double {
        plan.targetDistance(secondsPerMeter: planStore.pace(for: plan.activity).secondsPerMeter)
    }

    /// "Surprise me": picks a destination whose estimated route distance fits the plan.
    ///
    /// For now the estimate is straight-line × 1.25. Section B replaces it with real walking-route
    /// distances and a wider ring search.
    /// Preference order: partners with a live quest → other partners → real places.
    /// Randomized within the best tier so "surprise" stays surprising.
    func surpriseDestination(for plan: RunPlan) -> (PlannedDestination, String)? {
        guard let here = currentLocation else { return nil }
        let range = plan.destinationRange(target: targetDistance(for: plan))

        struct Candidate { let destination: PlannedDestination; let estimate: Double; let tier: Int }
        let partnerCandidates = partners.map { business in
            let live = business.isSlow && questStore.openQuest(for: business.id) != nil
            return Candidate(destination: PlannedDestination(business: business),
                             estimate: here.distance(from: business.location) * QuestMatcher.streetFactor,
                             tier: live ? 0 : 1)
        }
        let placeCandidates = places.places.map { place in
            Candidate(destination: PlannedDestination(place: place),
                      estimate: here.distance(from: place.location) * QuestMatcher.streetFactor, tier: 2)
        }
        let all = partnerCandidates + placeCandidates
        guard !all.isEmpty else { return nil }

        let fitting = all.filter { range.contains($0.estimate) }
        if let bestTier = fitting.map(\.tier).min(),
           let pick = fitting.filter({ $0.tier == bestTier }).randomElement() {
            return (pick.destination, "Surprise pick")
        }
        // Nothing in range yet: take whatever is closest to the middle of the range.
        let middle = (range.lowerBound + range.upperBound) / 2
        guard let closest = all.min(by: { abs($0.estimate - middle) < abs($1.estimate - middle) }) else { return nil }
        return (closest.destination, "Closest match nearby")
    }

    // MARK: Places

    func refreshNearbyPlaces() {
        guard let here = currentLocation else { return }
        places.forceRefresh(around: here)
    }

    // MARK: Run controls

    /// Starts a run from the "Plan your run" sheet. The plan is saved as next time's default.
    func startRun(with plan: RunPlan) {
        planStore.save(plan)
        activePlan = plan
        if plan.surpriseMe, let (pick, note) = surpriseDestination(for: plan) {
            setDestination(pick, note: note)
            mapFocus = pick.isPartner ? .partner(pick.id) : .place(pick.id)
        }
        run.start(targetDistance: targetDistance(for: plan))
        location.setBackgroundTracking(true)
        // Ask for permissions at the moment they matter: when a run actually starts.
        if location.authorization == .authorizedWhenInUse {
            location.requestAlways()
        }
        NotificationService.requestAuthorizationIfNeeded()
    }

    func pauseRun() { run.pause() }
    func resumeRun() { run.resume() }

    func endRun() {
        run.end()
        location.setBackgroundTracking(false)
        if let plan = activePlan, let pace = run.averagePace {
            planStore.recordPace(pace, distance: run.distanceMeters, activity: plan.activity)
        }
    }

    /// "Done" on the finished-run card.
    func resetRun() {
        run.reset()
        activePlan = nil
        if acceptedQuest == nil { clearDestination() }
    }
}
