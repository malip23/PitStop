import UserNotifications

/// Local notifications for quest offers. While the app is open, the in-app banner shows instead
/// (iOS doesn't present local notifications in the foreground unless asked to).
enum NotificationService {
    static func requestAuthorizationIfNeeded() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    static func notifyQuestOffer(_ offer: QuestOffer) {
        let content = UNMutableNotificationContent()
        content.title = "\(offer.business.name) is slow right now"
        content.body = "Run there for: \(offer.quest.reward) · \(Format.shortDistance(offer.extraDistance)) detour"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "quest-\(offer.quest.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
