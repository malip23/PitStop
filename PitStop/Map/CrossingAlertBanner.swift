import SwiftUI

/// Sun-yellow warning shown under the navigation banner when a crossing is close.
struct CrossingAlertBanner: View {
    let point: CrossingPoint
    let distance: Double

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .symbolEffect(.pulse)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(point.kind.title): \(point.kind.advice.lowercased())")
                    .font(.subheadline.weight(.bold))
                Text(distance > 3 ? "In \(Format.shortDistance(distance))" : "Now")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .opacity(0.8)
            }
            Spacer(minLength: 0)
            Image(systemName: point.kind.symbol).font(.title3)
        }
        .foregroundStyle(.black.opacity(0.85))
        .padding(12)
        .background(Theme.sun, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
    }
}

/// Map icon for an upcoming crossing; larger and pulsing while it's the active alert.
struct CrossingMarker: View {
    let point: CrossingPoint
    var isActive = false

    var body: some View {
        ZStack {
            if isActive { PulseRing(color: Theme.sun, size: 30, scale: 2) }
            Image(systemName: isActive ? "exclamationmark.triangle.fill" : point.kind.symbol)
                .font(.system(size: isActive ? 14 : 10, weight: .bold))
                .foregroundStyle(.black.opacity(0.8))
                .frame(width: isActive ? 30 : 20, height: isActive ? 30 : 20)
                .background(Theme.sun, in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(radius: 2)
        }
        .animation(.spring(duration: 0.3), value: isActive)
    }
}
