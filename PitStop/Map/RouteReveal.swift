import CoreLocation

/// Helpers for the "route draws itself" animation.
extension Array where Element == CLLocationCoordinate2D {
    /// The first `fraction` (0–1) of the polyline by distance, ending exactly at the interpolated point,
    /// so the line grows smoothly instead of jumping from vertex to vertex.
    func prefix(fraction: Double) -> [CLLocationCoordinate2D] {
        guard count > 1, fraction < 1 else { return self }
        guard fraction > 0 else { return [self[0]] }
        var total = 0.0
        for (a, b) in zip(self, dropFirst()) { total += a.distance(to: b) }
        var remaining = total * fraction
        var result = [self[0]]
        for (a, b) in zip(self, dropFirst()) {
            let segment = a.distance(to: b)
            if remaining <= segment {
                let t = segment > 0 ? remaining / segment : 0
                result.append(CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                                     longitude: a.longitude + (b.longitude - a.longitude) * t))
                return result
            }
            remaining -= segment
            result.append(b)
        }
        return result
    }
}
