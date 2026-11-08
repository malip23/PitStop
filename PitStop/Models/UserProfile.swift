import FirebaseFirestore
import Foundation

/// Firestore document `users/{uid}`.
/// Users may edit their own profile but never their own `role` (enforced in firestore.rules).
struct UserProfile: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var displayName: String
    var email: String
    var role: UserRole
    var createdAt: Date
    var lastActiveAt: Date
    var linkedBusinessId: String?
}
