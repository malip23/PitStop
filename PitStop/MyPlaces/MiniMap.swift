import MapKit
import SwiftUI

/// Small, non-interactive map thumbnail centered on one point.
struct MiniMap: View {
    let point: GeoPoint
    var tint: Color = Theme.lime

    var body: some View {
        Map(initialPosition: .camera(MapCamera(centerCoordinate: point.coordinate, distance: 700))) {
            Annotation("", coordinate: point.coordinate) {
                Circle().fill(tint).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 2))
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .disabled(true)
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
