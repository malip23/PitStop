import SwiftUI

/// Map annotation for a REAL place that isn't on PitStop yet: small, gray, and quiet,
/// so partner pins stand out.
struct RealPlacePin: View {
    let place: RealPlace
    var isSelected = false

    var body: some View {
        Image(systemName: place.category.symbol)
            .font(.system(size: isSelected ? 14 : 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: isSelected ? 32 : 22, height: isSelected ? 32 : 22)
            .background(.thinMaterial, in: Circle())
            .overlay(Circle().stroke(Color.secondary.opacity(0.35), lineWidth: 1))
            .opacity(isSelected ? 1 : 0.85)
            .animation(.spring(duration: 0.3), value: isSelected)
    }
}
