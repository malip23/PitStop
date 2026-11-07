import Foundation

/// Client-side throttling so the app stays under Gemini's free-tier limits:
/// - spaces calls at least `minInterval` apart per task (waits instead of firing a burst)
/// - counts calls per day per task, with a soft cap (persisted, resets at midnight)
/// - after a 429, pauses that task until the server's retry time has passed
@MainActor
final class AIRateLimiter {
    private var nextAllowed: [AIConfig.Task: Date] = [:]
    private(set) var coolingDownUntil: [AIConfig.Task: Date] = [:]
    private let defaults = UserDefaults.standard

    func callsToday(_ task: AIConfig.Task) -> Int {
        defaults.integer(forKey: dayKey(task))
    }

    /// Waits for this task's slot, or throws if today's budget is spent or a cooldown is active.
    func acquire(_ task: AIConfig.Task) async throws {
        if callsToday(task) >= task.dailyCap { throw AIError.dailyLimitReached }
        if let until = coolingDownUntil[task], until > .now {
            throw AIError.rateLimited(retryAfter: until.timeIntervalSinceNow)
        }
        let slot = max(nextAllowed[task] ?? .distantPast, .now)
        nextAllowed[task] = slot.addingTimeInterval(task.minInterval)
        let wait = slot.timeIntervalSinceNow
        if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
        defaults.set(callsToday(task) + 1, forKey: dayKey(task))
    }

    func coolDown(_ task: AIConfig.Task, for seconds: TimeInterval) {
        coolingDownUntil[task] = .now.addingTimeInterval(seconds)
    }

    private func dayKey(_ task: AIConfig.Task) -> String {
        let day = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
        return "ai.calls.\(task.rawValue).\(Int(day))"
    }
}
