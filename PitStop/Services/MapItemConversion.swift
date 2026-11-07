import MapKit

/// Converting MapKit search results into our own types. Shared by PlacesService and DestinationFinder.
extension RealPlace {
    /// Builds a RealPlace from a search result. `category` overrides the POI category when given
    /// (e.g. results from a "juice bar" text search).
    init?(mapItem item: MKMapItem, category: BusinessCategory? = nil) {
        guard let name = item.name, !name.isEmpty else { return nil }
        let placemark = item.placemark
        let coordinate = placemark.coordinate

        // Stable id: MapKit's own identifier when available, otherwise name + rounded coordinate.
        var id = "\(name)|\(String(format: "%.5f,%.5f", coordinate.latitude, coordinate.longitude))"
        if #available(iOS 18.0, *), let identifier = item.identifier {
            id = identifier.rawValue
        }

        let street = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let address = [street, placemark.locality ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")

        self.init(id: id, name: name,
                  category: category ?? BusinessCategory(poi: item.pointOfInterestCategory),
                  address: address.isEmpty ? nil : address,
                  latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

extension BusinessCategory {
    /// Maps Apple's POI category onto ours.
    init(poi: MKPointOfInterestCategory?) {
        switch poi {
        case .cafe?: self = .cafe
        case .bakery?: self = .bakery
        case .restaurant?: self = .restaurant
        case .fitnessCenter?: self = .fitness
        case .store?, .foodMarket?: self = .store
        default: self = .other
        }
    }
}
