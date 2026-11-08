import SwiftUI

/// Renders the PopupManager's current popup in its slot. Place one host for `.top` and one for
/// `.bottom`; only the slot matching the current popup draws anything.
struct PopupHost: View {
    @Environment(AppState.self) private var app
    let placement: PopupManager.Placement

    var body: some View {
        Group {
            if let popup = app.popups.current, popup.placement == placement {
                content(popup)
                    .id(popup.id)
                    .transition(.move(edge: placement == .top ? .top : .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: app.popups.current?.id)
    }

    @ViewBuilder private func content(_ popup: PopupManager.Popup) -> some View {
        switch popup.content {
        case .safety(let point):
            let distance = max(0, point.distanceAlongRoute - app.navigation.progress)
            PopupPill(symbol: "exclamationmark.triangle.fill", tint: Theme.sun, iconForeground: .black.opacity(0.85),
                      text: "\(point.kind.title): \(point.kind.advice.lowercased())",
                      trailing: distance > 3 ? Format.shortDistance(distance) : "Now",
                      onDismiss: { app.popups.dismiss(id: popup.id) }) {
                Label("Alerts are helpers. Always check traffic yourself.", systemImage: point.kind.symbol)
                    .foregroundStyle(.secondary)
            }

        case .offer(let offer):
            QuestOfferDock(offer: offer, deadline: app.offerDeadline(for: offer.quest.id)) {
                app.accept(offer)
                app.selectedTab = .run
            } onDismiss: {
                app.dismiss(offer)
            }

        case .suggestion(let suggestion):
            InterestSuggestionDock(suggestion: suggestion, isSaved: app.history.isSaved(suggestion.id),
                                   onAddStop: { app.addStop(suggestion) },
                                   onSave: { app.saveSuggestion(suggestion) },
                                   onDismiss: { app.dismissSuggestion(suggestion) })

        case .narration(let narration):
            PopupPill(symbol: narration.symbol, tint: Theme.lime, text: narration.text,
                      trailing: narration.destination != nil && !app.history.isSaved(narration.id) ? "Save?" : nil,
                      onDismiss: { app.popups.dismiss(id: popup.id) }) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Text("\(narration.name) · \(narration.kindName)")
                        if narration.usedAI { Image(systemName: "sparkles").foregroundStyle(Theme.sky) }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if let destination = narration.destination {
                        if app.history.isSaved(narration.id) {
                            Label("In your Future Places", systemImage: "bookmark.fill").font(.caption).foregroundStyle(Theme.sky)
                        } else {
                            HStack(spacing: 8) {
                                Text("Add to Future Places?").font(.subheadline.weight(.semibold))
                                Spacer()
                                Button("No") { app.popups.dismiss(id: popup.id) }
                                    .buttonStyle(.bordered).frame(minHeight: 44)
                                Button("Yes") {
                                    app.history.savePlace(destination, source: .narration)
                                    Haptics.success()
                                    app.popups.dismiss(id: popup.id)
                                }
                                .buttonStyle(.borderedProminent).frame(minHeight: 44)
                            }
                        }
                    }
                }
            }

        case .info(let info):
            PopupPill(symbol: info.symbol, tint: Theme.sky, text: info.title,
                      onDismiss: { app.popups.dismiss(id: popup.id) }) {
                if let message = info.message { Text(message).foregroundStyle(.secondary) }
            }
        }
    }
}
