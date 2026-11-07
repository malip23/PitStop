/// Who's using the app. Decides which tabs appear.
/// Set in Developer Settings for now; it moves to the Firestore user document once accounts exist.
enum UserRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case runner, admin

    var id: Self { self }
    var displayName: String { self == .runner ? "Runner" : "Admin" }
}
