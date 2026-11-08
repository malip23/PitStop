import UIKit

/// Spoken announcements for VoiceOver users (no effect when VoiceOver is off).
enum VoiceOver {
    static func announce(_ text: String) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}
