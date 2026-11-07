/// Lifecycle of a single run.
enum RunState: Equatable, Sendable {
    case idle
    case running
    case paused
    case finished
}
