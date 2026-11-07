import MapKit
import SwiftUI

/// A thick gradient polyline with a soft glow: a wide, semi-transparent line drawn underneath
/// the gradient line.
struct GlowingRoute: MapContent {
    let coordinates: [CLLocationCoordinate2D]
    var colors: [Color] = Theme.routeGradient
    var lineWidth: CGFloat = 7

    var body: some MapContent {
        // Glow underneath.
        MapPolyline(coordinates: coordinates)
            .stroke((colors.first ?? Theme.coral).opacity(0.28),
                    style: StrokeStyle(lineWidth: lineWidth * 2.6, lineCap: .round, lineJoin: .round))
        // Main gradient line.
        MapPolyline(coordinates: coordinates)
            .stroke(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }
}
