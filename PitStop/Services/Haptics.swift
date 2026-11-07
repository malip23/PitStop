import UIKit

/// Imperative haptics for events that don't originate from a view (quest offers, check-in).
/// Views can also use SwiftUI's `.sensoryFeedback` directly.
enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func tap() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
}
