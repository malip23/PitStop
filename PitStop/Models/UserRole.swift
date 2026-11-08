/// Who's using the app. Stored in Firestore `users/{uid}.role` and decides which tabs appear.
/// New accounts are always "runner"; admins are set in the Firebase console (see README).
nonisolated enum UserRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case runner, business, admin

    var id: Self { self }

    var displayName: String {
        switch self {
        case .runner: "Runner"
        case .business: "Business"
        case .admin: "Admin"
        }
    }

    /// Business and admin accounts can create and run (mock) businesses.
    var canManageBusinesses: Bool { self != .runner }
}
