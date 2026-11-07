import MapKit
import SwiftUI

/// A small map where a long-press drops (or moves) the business pin.
///
/// SwiftUI's Map has no long-press-with-location API, so we sequence a LongPressGesture into a
/// zero-distance DragGesture (which does report a location), then convert that screen point to a
/// coordinate with MapReader's proxy.
struct LocationPickerMap: View {
    @Binding var coordinate: CLLocationCoordinate2D?
    var onDrop: (CLLocationCoordinate2D) -> Void = { _ in }

    @State private var camera: MapCameraPosition

    init(coordinate: Binding<CLLocationCoordinate2D?>, onDrop: @escaping (CLLocationCoordinate2D) -> Void = { _ in }) {
        _coordinate = coordinate
        self.onDrop = onDrop
        if let c = coordinate.wrappedValue {
            _camera = State(initialValue: .camera(MapCamera(centerCoordinate: c, distance: 1200)))
        } else {
            _camera = State(initialValue: .userLocation(fallback: .automatic))
        }
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $camera) {
                UserAnnotation()
                if let coordinate {
                    Marker("New business", systemImage: "storefront.fill", coordinate: coordinate)
                        .tint(Color.accentColor)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .including([.cafe, .bakery, .restaurant, .store, .fitnessCenter])))
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onEnded { value in
                        guard case .second(true, let drag?) = value,
                              let point = proxy.convert(drag.location, from: .local) else { return }
                        coordinate = point
                        onDrop(point)
                        Haptics.tap()
                    }
            )
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .bottom) {
            Text(coordinate == nil ? "Long-press the map to drop a pin" : "Long-press again to move the pin")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .padding(8)
        }
    }
}
