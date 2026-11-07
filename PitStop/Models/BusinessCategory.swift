import SwiftUI

/// The kind of business or place. Shared by real MapKit places and partner businesses.
/// Drives the map pin icon, labels, and reward suggestions.
enum BusinessCategory: String, Codable, CaseIterable, Sendable {
    case cafe, bakery, juicery, smoothieBar, restaurant, fitness, store
    case bikeShop, yogaStudio, bookstore, gelato, other

    var displayName: String {
        switch self {
        case .cafe: "Café"
        case .bakery: "Bakery"
        case .juicery: "Juice Bar"
        case .smoothieBar: "Smoothie Bar"
        case .restaurant: "Restaurant"
        case .fitness: "Fitness Center"
        case .store: "Store"
        case .bikeShop: "Bike Shop"
        case .yogaStudio: "Yoga Studio"
        case .bookstore: "Bookstore"
        case .gelato: "Gelato"
        case .other: "Local Spot"
        }
    }

    /// SF Symbol used on the map pin and in lists.
    var symbol: String {
        switch self {
        case .cafe: "cup.and.saucer.fill"
        case .smoothieBar: "takeoutbag.and.cup.and.straw.fill"
        case .bikeShop: "bicycle"
        case .yogaStudio: "figure.yoga"
        case .bakery: "birthday.cake.fill"
        case .bookstore: "book.fill"
        case .gelato: "snowflake"
        case .juicery: "leaf.fill"
        case .restaurant: "fork.knife"
        case .fitness: "dumbbell.fill"
        case .store: "bag.fill"
        case .other: "mappin"
        }
    }

    /// One-tap reward ideas shown in Business mode.
    var suggestedRewards: [String] {
        switch self {
        case .cafe: ["Free cold brew", "50% off any latte", "Free pastry with coffee"]
        case .smoothieBar: ["Free protein boost", "$3 off any smoothie", "Free small smoothie"]
        case .bikeShop: ["Free tire pump-up", "15% off accessories", "Free chain lube"]
        case .yogaStudio: ["Free drop-in stretch class", "50% off first class", "Free mat rental"]
        case .bakery: ["Free croissant", "Buy one get one muffin", "20% off bread"]
        case .bookstore: ["10% off any book", "Free bookmark + tea", "$5 off running books"]
        case .gelato: ["Free mini scoop", "Free topping", "2-for-1 scoops"]
        case .juicery: ["Free wellness shot", "$2 off cold-pressed juice", "Free electrolyte refill"]
        case .restaurant: ["Free side with any entrée", "15% off your meal", "Free drink"]
        case .fitness: ["Free day pass", "Free recovery session", "50% off first class"]
        case .store: ["10% off your purchase", "Free water bottle", "$5 off $25"]
        case .other: ["Free treat", "10% off", "Free drink"]
        }
    }
}
