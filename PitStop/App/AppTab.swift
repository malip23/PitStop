/// The top-level tabs. Kept in AppState so popups know whether the map is on screen.
enum AppTab: Hashable {
    case run, myPlaces, rewards, business, admin, settings
}
