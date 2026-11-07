import SwiftUI

/// Shown when location access is missing, with a shortcut to Settings.
struct LocationPermissionCard: View {
    @Environment(AppState.self) private var app

    var body: some View {
        MaterialCard(padding: 14) {
            HStack {
                Image(systemName: "location.slash.fill").foregroundStyle(.orange)
                Text("Location is needed to track runs and find nearby places.")
                    .font(.subheadline)
                Spacer()
                Button(app.location.authorization == .notDetermined ? "Allow" : "Settings") {
                    if app.location.authorization == .notDetermined {
                        app.location.requestWhenInUse()
                    } else if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
