import MapKit
import SwiftUI

/// "Places I've run to" and saved places on one map: lime ✓ for visited, sky bookmark for future.
struct PlacesMapView: View {
    let visited: [VisitedPlace]
    let future: [SavedPlace]

    var body: some View {
        Map(initialPosition: .automatic) {
            ForEach(visited) { place in
                Annotation(place.name, coordinate: place.point.coordinate, anchor: .bottom) {
                    pin(symbol: "checkmark", color: Theme.lime, count: place.visitCount)
                }
            }
            ForEach(future) { place in
                Annotation(place.name, coordinate: place.point.coordinate, anchor: .bottom) {
                    pin(symbol: "bookmark.fill", color: Theme.sky, count: nil)
                }
            }
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
        .overlay {
            if visited.isEmpty && future.isEmpty {
                ContentUnavailableView("No places yet", systemImage: "map",
                                       description: Text("Places you check in at and save for later appear here."))
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                    .padding(40)
            }
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 16) {
                Label("Visited \(visited.count)", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.lime)
                Label("Future \(future.count)", systemImage: "bookmark.fill").foregroundStyle(Theme.sky)
            }
            .font(.caption.weight(.bold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 12)
        }
    }

    private func pin(symbol: String, color: Color, count: Int?) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(color.gradient, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2.5))
            .overlay(alignment: .topTrailing) {
                if let count, count > 1 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Theme.coralDeep, in: Circle())
                        .offset(x: 6, y: -6)
                }
            }
            .shadow(radius: 3)
    }
}
