# PitStop

**Surge pricing in reverse for small businesses.**

Every café, bakery, and bike shop has dead hours: the mid-afternoon lull when staff are paid but the
room is empty. Discount apps fill those hours with bargain hunters who never come back. PitStop fills
them with people who are already out moving.

When a local business is quiet, it taps **"We're slow right now"** and sets a reward ("Free cold
brew"). Runners and walkers nearby get a **time-limited Off-Peak Quest**. PitStop reroutes their run so
it ends at that business at the distance they wanted anyway, and a **verified check-in** unlocks the
reward. The business gets foot traffic exactly when it needs it; the runner gets a better run, a
reason to explore, and a perk.

Built in Swift for iPhone (iOS 17+), with Apple frameworks, Google Gemini, OpenStreetMap, and Firebase.

---

## The experience

### For runners
1. **Plan the run you want.** Run, walk, or bike; a distance (1–10 mi) or a time (15–90 min, converted
   with your own pace); one-way or out-and-back; or "Surprise me".
2. **Pick a destination that fits.** PitStop finds real places at the right distance, ranked by how
   closely the real walking route matches your goal. Businesses with live Off-Peak Quests come first.
3. **Get a route worth running.** 2–3 real route options, plus an **AI-suggested scenic route**
   (parks, waterfronts, quieter streets) that is verified against Apple Maps before it's shown.
4. **Run with a guide.** Turn-by-turn directions, **crosswalk and traffic-signal alerts** from
   OpenStreetMap, a **city guide** that briefly introduces landmarks you pass, and **quick-stop
   suggestions** for places you love ("Smoothie shop 2 blocks ahead, +0.2 mi. Stop by?").
5. **Get time-limited offers.** If a partner nearby goes quiet mid-run, a 30-second offer appears.
   Accept, and the route bends to include it.
6. **Check in and collect.** Stay 10 seconds at the destination. If anti-cheat verifies the run, you
   unlock the partner's reward, a **passport stamp** for every new place, and **milestone badges**.

### For businesses
- Create a business (or link to a real one on the map), set a reward, and flip **We're slow right now**.
- Watch it work live: offers shown / accepted / expired, **"Runner arriving in 3:42"** with a countdown,
  and **recent check-ins** marked verified or not.
- Businesses only ever see visits, quests, and arrival times, **never runner health data, routes, or names.**

### For admins
An **Admin** tab with live stats (users, active quests, verified visits, total runs), every user with
role management, and tools to inspect or delete businesses, quests, and demo data.

---

## What makes it work

### 1. Goal-matched destinations (`Routing/DestinationFinder.swift`)
A destination should be 70–100% of the goal away (one-way) or 40–50% (out-and-back). One MapKit search
returns only a limited number of places, so PitStop searches **six points spaced around a ring** at that
radius, merges and de-duplicates the results, then measures the **real walking route** to the best
candidates (a few at a time, cached) and keeps those within **±15% of the goal**. Partners with a live
quest that are too close are kept and marked "extend", because the route generator can lengthen the trip.

### 2. Route generation without waypoints (`Routing/RouteGenerator.swift`)
Apple Maps only routes A → B. To make a 0.8-mile-away café a 3-mile run, PitStop inserts waypoints. Every
point whose distances to the start and the destination add up to a fixed budget lies on an **ellipse**
with the start and destination as its foci. PitStop places candidate waypoints on that ellipse (budget =
goal ÷ 1.25, because streets are about 25% longer than straight lines), routes each candidate for real,
applies **one correction pass** (scale the budget by goal ÷ actual), and returns the closest fits.
Out-and-back runs become loops: out on one side, back on the other.

### 3. Grounded AI agents (`AI/`, `Routing/RouteAgent.swift`, `MyPlaces/RecommendationEngine.swift`)
The AI never invents paths, places, or distances.
- **Route agent:** Gemini gets three function tools, all backed by MapKit: `get_user_preferences`,
  `search_places_near` (real parks, landmarks, waterfronts), and `get_walking_routes` (routes candidate
  waypoint sets and returns real distances, times, and turns). It must answer by choosing a candidate ID.
  Swift then checks that the route exists, reaches the destination, and is within 10% of the goal; if
  not, the algorithmic route is used.
- **Recommender:** the app gathers the candidates (promotions, new partners, places matching your
  interests within your goal distance); Gemini may only choose from that list by ID and writes a short,
  personal reason. Unknown IDs are rejected.
- **City guide and quick stops:** all narration lines are pre-fetched in one batched request at route start,
  using only the place data we send (name, category, address, side of the street, our notes), with an
  explicit instruction not to invent history or facts.

Every AI feature has a **non-AI fallback**, so the app works fully offline or when free-tier limits are
hit; a small "AI unavailable" note explains it. The service layer (`AIService`) is provider-agnostic, and
`GeminiService` handles caching, de-duplication, throttling, 429 backoff, and model fallback.

### 4. Navigation and safety (`Routing/NavigationEngine.swift`, `Routing/CrossingAlertEngine.swift`)
The runner is snapped to the route by searching **forward from the last match**, so out-and-back routes
(which overlap themselves) don't jump to the return leg. More than 40 m off route twice in a row offers a
reroute. Crossings and signals come from the OpenStreetMap Overpass API for the route's bounding box,
are kept only if within 15 m of the path (counted once per pass), merged within 20 m, combined with turns,
and alerted once at 30 m. If Overpass is unavailable, turn-based alerts still work.

### 5. One popup at a time (`Views/Popups/PopupManager.swift`)
Safety alerts, timed offers, quick-stop suggestions, and narration share a single slot with a priority
queue: **safety › offers › suggestions › narration**. Safety pre-empts; everything else waits its turn.
Popups are slim and docked so the map and route stay visible; the camera offsets itself to keep the
runner in the visible gap.

### 6. Fair offers (`Quests/QuestMatcher.swift`, `Quests/OfferTiming.swift`)
A quest is offered only if the detour is under 1.5 miles. Offers are ranked by **closeness (50%)**, **how
long the business has been slow (25%)**, and a **fair-discovery boost (25%)** for places with fewer recent
visits, so the same popular café doesn't win every time. Offers last **30 seconds** (green → yellow →
red), with haptics, VoiceOver announcements, and Reduce Motion support.

### 7. Verified visits (`AntiCheat/`, `Quests/CheckInMonitor.swift`)
Rewards only count for real effort. A check-in requires 10 seconds within 30 m of the place (or the
route's street-side arrival point). Anti-cheat compares **step cadence (CoreMotion) with GPS speed** and
flags runs that are too fast for the activity, have almost no steps while moving, use **software-simulated
locations**, or show **impossible position jumps**. Only verified runs earn rewards, stamps, and badges.

---

## Privacy by design
- **No health data.** PitStop doesn't read HealthKit; a run stores only distance, time, route, and the
  anti-cheat verdict. Step counts are used on-device for verification and never uploaded.
- **AI sees the minimum:** rounded start coordinates (~100 m), public place names and categories,
  interests, and goals. Never names, emails, or health data.
- **Businesses see visits, not people:** a visit is a runner ID, a verified flag with reasons, and a time.
- **Server-enforced roles:** `firestore.rules` lets users read and write only their own profile, runs,
  rewards, and saved places; nobody can change their own role; only a business's owner or an admin can
  edit it; runners may only touch the runner fields of a quest.
- **API key off the device** (recommended setup): Gemini calls go through a Cloudflare Worker that holds
  the key and only allows PitStop's models.

## Accessibility
Dynamic Type throughout, 44-pt tap targets, VoiceOver labels and announcements (offers, alerts,
narration), Reduce Motion support for animations and countdowns, haptics for every key event, light and
dark mode, and a natural-sounding voice (Premium/Enhanced voices, or the user's own Personal Voice).

---

## Architecture

```
User goals + interests + My Places
        │
        ▼
Gemini agents (AIService)  ──►  route planner with MapKit function tools
                             └► recommender over app-provided candidates
        │                       (always validated by MapKit; non-AI fallbacks everywhere)
        ▼
Navigation: turn-by-turn · AI city guide · OpenStreetMap crossing alerts
            · quick-stop suggestions · timed Off-Peak offers, through one priority PopupManager
        │
        ▼
On-device CoreMotion + GPS anti-cheat → verified check-in
        │
        ▼
Verified visits → history, My Places, stamps, badges, partner rewards
        │
        ▼
Firestore real-time sync (runner phone ↔ business phone), offline-first
```

**Pattern:** SwiftUI + `@Observable` MVVM. `AppState` is the composition root and owns a **single location
pipeline**: every GPS fix (or simulated fix in Demo Mode) flows through `handleLocation` to the run
tracker, navigation, crossing alerts, check-in, anti-cheat, suggestions, narration, and quest matching.

**Data:** SwiftData on device (fast, offline) mirrored to Firestore:

| Collection | Contents | Access |
|---|---|---|
| `users/{uid}` | name, email, role, createdAt, lastActiveAt | self; admins |
| `users/{uid}/runs` · `/rewards` · `/savedPlaces` | run history, stamps/badges/perks, Future Places | self only |
| `businesses/{id}` | partner businesses (demo ones flagged) | read: signed in · write: owner/admin |
| `quests/{id}` | Off-Peak Quests, live ETA, offer stats | read: signed in · runners: runner fields only |
| `visits/{id}` | check-ins (verdict only) | runner, business owner, admin |

**Code map**

| Folder | What's inside |
|---|---|
| `App/` | `AppState` (composition root), root views, tabs |
| `AI/` | `AIService` protocol, `GeminiService`, `AgentRunner` (function-calling loop) |
| `Routing/` | destination finder, route generator, route agent, navigation, crossing alerts, suggestions, narration |
| `Map/` | the map screen, pins, cards, route options |
| `Quests/` · `Business/` | quest matching, timed offers, check-in · business dashboard and stores |
| `MyPlaces/` · `Rewards/` | Visited/Future places, recommendations · stamps, badges, history |
| `AntiCheat/` | CoreMotion steps and verification |
| `Services/` | location, places, speech, Firebase auth and sync, history store |
| `Admin/` | admin tab |
| `proxy/` | Cloudflare Worker for the Gemini key |

**Tech:** SwiftUI, MapKit, CoreLocation, CoreMotion, SwiftData, AVFoundation, UserNotifications,
FirebaseAuth, Cloud Firestore, Google Gemini (`gemini-3.8-flash`, `gemini-3.5-flash-lite`),
OpenStreetMap Overpass, Cloudflare Workers.

---

## Setup

1. Open `PitStop.xcodeproj`, select the **PitStop** target, and set your signing team.
2. **Firebase** (`GoogleService-Info.plist` is included):
   - Authentication → Sign-in method → enable **Email/Password**.
   - Firestore Database → Create database (production mode).
   - Firestore → Rules → paste `firestore.rules` → Publish.
3. **Gemini (optional; everything has a fallback):**
   - Recommended: deploy `proxy/` (see `proxy/README.md`), then set `AI_PROXY_HOST` (host only, no
     `https://`) and `AI_PROXY_TOKEN` in `Secrets.xcconfig`.
   - Or set `GEMINI_API_KEY` in `Secrets.xcconfig` (git-ignored; copy `Secrets.example.xcconfig`).
   - `Config.xcconfig` must be the base configuration for Debug and Release (Project → Info).
4. Run on an iPhone. On first launch, trust the developer certificate in Settings → General → VPN &
   Device Management.

**Make an admin:** sign up in the app, then in the Firebase console open Firestore → `users` → your
document → set `role` to `admin`. The app updates instantly. New accounts are always runners, and users
can never change their own role.

**Developer tools** (Settings): Demo Mode plays a run along the chosen route indoors; anti-cheat can be
turned off for Xcode location simulation; "Fake run at car speed" shows a rejected run; Settings → AI runs
live checks of the Gemini connection.

## Limitations and next steps
- Heart-rate-based effort scoring (Apple Watch / HealthKit) is a future step; the run model already
  reserves an `effortScore` field, and any health data would stay on-device.
- Free-tier Gemini limits are respected client-side; production would move rate limiting into the Worker.
- Partner onboarding (verifying a real business owns its listing) is out of scope; demo businesses are
  clearly marked.
