import SwiftUI

/// Custom "you are here" marker: sky-blue dot with a soft pulse and a heading arrow.
///
/// `heading` is degrees clockwise from north; `mapHeading` is the camera's rotation. The arrow is drawn
/// at their difference so it still points the right way when the map is rotated.
struct UserLocationMarker: View {
    var heading: Double?
    var mapHeading: Double = 0

    var body: some View {
        ZStack {
            PulseRing(color: Theme.sky, size: 26, scale: 2.2, duration: 2)

            if let heading {
                // Heading cone/arrow, offset outward from the dot.
                Image(systemName: "location.north.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.sky)
                    .offset(y: -20)
                    .rotationEffect(.degrees(heading - mapHeading))
                    .animation(.easeOut(duration: 0.25), value: heading)
            }

            Circle()
                .fill(Theme.sky.gradient)
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(.white, lineWidth: 3.5))
                .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
        }
        .frame(width: 60, height: 60)
        .accessibilityLabel("Your location")
    }
}
