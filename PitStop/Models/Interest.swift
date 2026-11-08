/// Things a runner likes to pass or visit. Used by the AI route agent (scenic choices) and,
/// later, the recommender.
nonisolated enum Interest: String, CaseIterable, Identifiable, Codable, Sendable {
    case coffee, bakeries, parks, bookstores, smoothies, gyms, vintage, museums, waterfront, streetArt, food, music

    var id: Self { self }

    var displayName: String {
        switch self {
        case .coffee: "Coffee"
        case .bakeries: "Bakeries"
        case .parks: "Parks"
        case .bookstores: "Bookstores"
        case .smoothies: "Smoothies"
        case .gyms: "Gyms"
        case .vintage: "Vintage shops"
        case .museums: "Museums"
        case .waterfront: "Waterfront"
        case .streetArt: "Street art"
        case .food: "Food spots"
        case .music: "Live music"
        }
    }

    var symbol: String {
        switch self {
        case .coffee: "cup.and.saucer.fill"
        case .bakeries: "birthday.cake.fill"
        case .parks: "tree.fill"
        case .bookstores: "book.fill"
        case .smoothies: "takeoutbag.and.cup.and.straw.fill"
        case .gyms: "dumbbell.fill"
        case .vintage: "tshirt.fill"
        case .museums: "building.columns.fill"
        case .waterfront: "water.waves"
        case .streetArt: "paintpalette.fill"
        case .food: "fork.knife"
        case .music: "music.note"
        }
    }

    /// Our business categories that match this interest (used by the recommender).
    var categories: [BusinessCategory] {
        switch self {
        case .coffee: [.cafe]
        case .bakeries: [.bakery]
        case .smoothies: [.smoothieBar, .juicery]
        case .gyms: [.fitness, .yogaStudio]
        case .bookstores: [.bookstore]
        case .vintage: [.store]
        case .food: [.restaurant, .gelato]
        case .parks, .museums, .waterfront, .streetArt, .music: []
        }
    }
}
