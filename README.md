# PitStop

**Surge pricing in reverse for small businesses.** A business taps "We're slow right now" and sets a
reward. Nearby runners get a live **Off-Peak Quest** to run there and unlock it.

SwiftUI · iOS 17+ · `@Observable` MVVM · MapKit · CoreLocation · UserNotifications. No API keys needed
for maps or places.

> Status: Milestone 1 (map + run tracking), real nearby places, and mock partner businesses with
> Off-Peak Quests are done. Coming next: run goals, goal-matched destinations, routing and navigation,
> run history, digital rewards, then Firebase sync, accounts, and admin.

## Setup

1. Open `PitStop.xcodeproj` in Xcode.
2. Select the **PitStop** target → *Signing & Capabilities* → make sure your team is selected.
3. Plug in your iPhone, choose it as the run destination, and press **⌘R**.
4. First launch only: on the iPhone, go to **Settings → General → VPN & Device Management** and trust
   your developer certificate, then run again.

## Real places vs. partner businesses

| | Real places | Partner businesses |
|---|---|---|
| Source | Apple Maps search (`MKLocalPointsOfInterestRequest` + `MKLocalSearch`) | Created in the Business tab (mock/demo for now) |
| Map pin | Small, gray, muted | Large, orange, gift badge when a quest is live, **DEMO** badge if mock |
| Label | "Not on PitStop yet" | "PitStop partner" |
| Rewards / quests | **Never**. They haven't agreed to offer any. | Yes |
| Used by quest matching & routing | No | **Yes, the only input** |

Real places are searched in about a 1.5 km radius (cafés, bakeries, juice/smoothie shops,
restaurants, fitness centers, stores), cached on disk, and refreshed after you move about 600 m.

## How to create a mock business

1. Open the **Business** tab → **Create Mock Business**.
2. Enter a **name**, pick a **category**, and type a **reward** (or tap a suggestion like "Free cold brew").
3. Choose the location with one of the three **Location** options:
   - **Drop pin**: long-press the small map; long-press again to move the pin. The address is looked up automatically.
   - **Current**: tap *Use my current location*.
   - **Real place**: see below.
4. Tap **Save**. You land on the business's dashboard.
5. Flip **We're slow right now** on. An Off-Peak Quest goes live immediately.

Edit with **Edit** on the dashboard; delete by swiping the row or with **Delete Business** in the editor.
Mock businesses are saved to `Documents/businesses.json` and survive relaunches.

### Linking a mock business to a real place

In the editor, choose **Location → Real place → Choose a nearby place** and pick from the list (searchable,
sorted by distance). PitStop copies the place's **name, address, coordinates, and category** and records
it as `linkedRealPlaceName`. The real place's pin stays muted; your mock partner pin (with the DEMO
badge) sits on top of it with the reward.

## How quests are matched and ranked (`QuestMatcher`)

- **Eligible:** a partner business that is slow, has an active quest, and is within **1.5 mi** of extra
  distance (straight line × 1.25 street factor).
- **Score** (0–100, shown in the Quests tab):
  - 50% **closeness**: smaller detour = higher
  - 25% **urgency**: how long the business has been slow (maxes out at 60 min)
  - 25% **fair discovery**: fewer visits in the last 30 days = bigger boost, so the popular spot doesn't always win
- The best new offer appears as a **banner with haptics** (on every tab except Business) plus a **local
  notification** if the app is in the background.

## Demo script (one phone, for now)

1. **Run tab:** show the map. Gray pins are real places; tap one: "Not on PitStop yet," no reward.
2. **Business tab → Create Mock Business →** link it to a real café nearby → Save.
3. On the dashboard, flip **We're slow right now** → the card glows and the "Slow for…" timer starts.
4. Switch to **Run**. The **Off-Peak Quest banner** drops in with a haptic. The business pin now pulses
   with a gift badge and a DEMO tag.
5. **Quests tab:** show the ranked list and the score breakdown (Close / Slow / Discover).
6. Tap **Accept**. The map flies to frame you and the business; "Quest accepted" card appears.
7. Back on the dashboard: "A runner accepted. They're on the way!"

*Two-phone sync (runner phone ↔ business phone) arrives with the Firebase backend.*

## Architecture

```
App/        AppState (composition root, single location pipeline), RootTabView
Models/     Business, Quest, QuestOffer, RealPlace, BusinessCategory, RunState
Services/   LocationService, PlacesService (MapKit search + cache), LocalFileStore (JSON),
            NotificationService, ReverseGeocoder, Geo, Format, Haptics
Map/        RunMapScreen, RunTracker, pins, detail cards, RunStatsCard
Quests/     QuestStore, QuestMatcher (ranking), QuestsScreen, offer banner/rows
Business/   BusinessStore, BusinessScreen, BusinessDashboardView, MockBusinessEditor, LocationPickerMap
```

Every location fix, real or simulated, flows through `AppState.handleLocation`, which feeds the run
tracker, nearby-places refresh, and quest matching. Stores persist plain Codable arrays whose fields
mirror the planned Firestore documents (`businesses/{id}`, `quests/{id}`).
