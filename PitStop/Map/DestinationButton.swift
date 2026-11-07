import SwiftUI

/// "Go here" on a pin's detail card. Sets it as the run destination.
struct DestinationButton: View {
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        if isCurrent {
            Label("Your destination", systemImage: "flag.checkered")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        } else {
            Button(action: action) {
                Label("Go here", systemImage: "flag.checkered").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }
}
