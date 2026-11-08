import ActivityKit
import Foundation

/// Starts, updates, and ends the run Live Activity.
///
/// Updates are throttled (every 5 s, or immediately for turns and offers) to stay within the
/// system's update budget. The elapsed timer ticks on its own on the Lock Screen (it's a timer
/// text driven by `timerStart`), so it doesn't need updates every second.
@MainActor
final class LiveActivityManager {
    private var activity: ActivityKit.Activity<RunActivityAttributes>?   // qualified: our app has its own `Activity` (run/walk/bike)
    private var lastState: RunActivityAttributes.ContentState?
    private var lastUpdate: Date = .distantPast
    private let minInterval: TimeInterval = 5

    var isRunning: Bool { activity != nil }

    func start(destinationName: String?, activitySymbol: String, state: RunActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end(immediately: true)
        let attributes = RunActivityAttributes(destinationName: destinationName, activitySymbol: activitySymbol)
        activity = try? ActivityKit.Activity.request(attributes: attributes,
                                         content: ActivityContent(state: state, staleDate: nil),
                                         pushType: nil)
        lastState = state
        lastUpdate = .now
    }

    /// Sends an update if enough time passed, or right away when `urgent` (new turn, offer change).
    func update(_ state: RunActivityAttributes.ContentState, urgent: Bool = false) {
        guard let activity, state != lastState else { return }
        guard urgent || Date.now.timeIntervalSince(lastUpdate) >= minInterval else { return }
        lastState = state
        lastUpdate = .now
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    /// Ends the activity, leaving the final stats on the Lock Screen for a couple of minutes.
    func end(finalState: RunActivityAttributes.ContentState? = nil, immediately: Bool = false) {
        guard let activity else { return }
        let content = (finalState ?? lastState).map { ActivityContent(state: $0, staleDate: nil) }
        let policy: ActivityUIDismissalPolicy = immediately ? .immediate : .after(.now.addingTimeInterval(120))
        Task { await activity.end(content, dismissalPolicy: policy) }
        self.activity = nil
        lastState = nil
    }
}
