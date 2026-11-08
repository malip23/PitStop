import Foundation
import Observation

/// One popup slot for the whole app, fed by a priority queue.
///
/// Priority (highest first): **safety** (crosswalks) › **offer** (timed discounts / quests) ›
/// **suggestion** (nearby interests) › **narration**.
///
/// Rules:
/// - Only one popup is visible at a time.
/// - A lower-priority popup waits in the queue until the current one closes.
/// - Safety is the exception: it pre-empts anything lower, and the interrupted popup goes back into the
///   queue to show again afterwards (unless it has expired by then).
/// - Popups can expire while waiting (e.g. a narration about a place already passed), and can
///   auto-dismiss after a set time once shown.
@Observable
final class PopupManager {
    enum Priority: Int, Comparable {
        case narration = 0, suggestion = 1, offer = 2, safety = 3
        static func < (a: Priority, b: Priority) -> Bool { a.rawValue < b.rawValue }
    }

    enum Placement { case top, bottom }

    /// Simple informational message (e.g. "Offer ended").
    struct Info: Hashable {
        let title: String
        let message: String?
        let symbol: String
    }

    enum Content: Hashable {
        case safety(CrossingPoint)
        case offer(QuestOffer)
        case suggestion(InterestSuggestion)
        case narration(Narration)
        case info(Info)

        var priority: Priority {
            switch self {
            case .safety: .safety
            case .offer: .offer
            case .suggestion: .suggestion
            case .narration, .info: .narration
            }
        }

        /// Safety and info are slim pills at the top; offers and suggestions dock at the bottom.
        var placement: Placement {
            switch self {
            case .offer, .suggestion: .bottom
            case .safety, .narration, .info: .top
            }
        }
    }

    struct Popup: Identifiable, Equatable {
        let id: String
        let content: Content
        let createdAt: Date
        /// Dropped from the queue if not shown by then.
        let expiresAt: Date?
        /// Auto-dismissed this many seconds after it appears.
        let autoDismissAfter: TimeInterval?

        var priority: Priority { content.priority }
        var placement: Placement { content.placement }
    }

    private(set) var current: Popup?
    /// Called every time a popup becomes visible (offers start their countdown here).
    @ObservationIgnored var onPresent: ((Popup) -> Void)?
    @ObservationIgnored private var queue: [Popup] = []
    @ObservationIgnored private var autoDismissTask: Task<Void, Never>?

    /// Adds a popup. Ignores duplicates (same id already showing or queued).
    func show(_ content: Content, id: String, expiresIn: TimeInterval? = nil, autoDismissAfter: TimeInterval? = nil) {
        guard current?.id != id, !queue.contains(where: { $0.id == id }) else { return }
        let popup = Popup(id: id, content: content, createdAt: .now,
                          expiresAt: expiresIn.map { .now.addingTimeInterval($0) },
                          autoDismissAfter: autoDismissAfter)

        if let current {
            if popup.priority == .safety && current.priority < .safety {
                queue.append(current)          // interrupted: show again later
                present(popup)
            } else {
                queue.append(popup)            // wait for its turn
            }
        } else {
            present(popup)
        }
    }

    /// Closes a popup (or removes it from the queue) and shows the next one.
    func dismiss(id: String) {
        queue.removeAll { $0.id == id }
        guard current?.id == id else { return }
        current = nil
        autoDismissTask?.cancel()
        showNext()
    }

    /// Removes every popup matching `predicate`, visible or queued.
    func remove(where predicate: (Popup) -> Bool) {
        queue.removeAll(where: predicate)
        if let current, predicate(current) { dismiss(id: current.id) }
    }

    func contains(where predicate: (Popup) -> Bool) -> Bool {
        (current.map(predicate) ?? false) || queue.contains(where: predicate)
    }

    // MARK: Private

    private func present(_ popup: Popup) {
        autoDismissTask?.cancel()
        current = popup
        onPresent?(popup)
        if let seconds = popup.autoDismissAfter {
            autoDismissTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                self?.dismiss(id: popup.id)
            }
        }
    }

    /// Highest priority first; oldest first within a priority. Expired popups are dropped.
    private func showNext() {
        queue.removeAll { ($0.expiresAt ?? .distantFuture) < .now }
        guard let next = queue.max(by: { a, b in
            a.priority != b.priority ? a.priority < b.priority : a.createdAt > b.createdAt
        }) else { return }
        queue.removeAll { $0.id == next.id }
        present(next)
    }
}
