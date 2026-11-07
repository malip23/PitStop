import SwiftUI

/// Map card for the quest the runner accepted. (Turn-by-turn routing replaces the straight-line
/// distance in section C.)
struct AcceptedQuestCard: View {
    @Environment(AppState.self) private var app
    let quest: Quest
    let business: Business

    var body: some View {
        MaterialCard(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: "flag.checkered")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.gradient, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quest accepted").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                    Text(quest.reward).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Cancel", role: .cancel) { app.cancelAcceptedQuest() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private var subtitle: String {
        guard let here = app.currentLocation else { return business.name }
        return "\(business.name) · \(Format.shortDistance(here.distance(from: business.location))) away"
    }
}
