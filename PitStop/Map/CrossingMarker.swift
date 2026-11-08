import SwiftUI

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
