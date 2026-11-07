import CoreLocation

/// Small geodesy helpers used by seeding, route generation, and the demo simulator.
extension CLLocationCoordinate2D {
    private static let earthRadius = 6_371_000.0

    /// Returns the coordinate reached by travelling `meters` from `self` along `bearingDegrees`
    /// (0 = north, 90 = east). Uses the standard great-circle destination formula.
    func offset(bearingDegrees: Double, meters: Double) -> CLLocationCoordinate2D {
        let angular = meters / Self.earthRadius
        let bearing = bearingDegrees * .pi / 180
        let lat1 = latitude * .pi / 180
        let lon1 = longitude * .pi / 180

        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(bearing))
        let lon2 = lon1 + atan2(sin(bearing) * sin(angular) * cos(lat1),
                                cos(angular) - sin(lat1) * sin(lat2))
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    /// Initial bearing (degrees, 0–360) from `self` to `other`.
    func bearing(to other: CLLocationCoordinate2D) -> Double {
        let lat1 = latitude * .pi / 180, lat2 = other.latitude * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Straight-line distance in meters.
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}

/// Unit helpers. Internally everything is meters and seconds.
enum Units {
    static let metersPerMile = 1609.344
}
