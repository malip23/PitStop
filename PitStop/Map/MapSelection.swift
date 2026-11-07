/// What the user tapped on the map. One selection type lets a single `Map(selection:)` handle both
/// partner businesses and real places.
enum MapSelection: Hashable {
    case partner(Business.ID)
    case place(RealPlace.ID)
}
