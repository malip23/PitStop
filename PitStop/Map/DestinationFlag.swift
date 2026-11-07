import SwiftUI

/// Checkered flag floating above the run's destination pin.
struct DestinationFlag: View {
    var body: some View {
        Image(systemName: "flag.checkered")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .padding(7)
            .background(Color.primary, in: Capsule())
            .overlay(Capsule().stroke(.white, lineWidth: 2))
            .shadow(radius: 3)
    }
}
