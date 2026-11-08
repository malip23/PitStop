import FirebaseAuth
import FirebaseFirestore
import Observation

/// Email/password accounts with FirebaseAuth, plus the live `users/{uid}` profile.
///
/// - Sessions persist between launches (FirebaseAuth keeps the user signed in).
/// - On first sign-up, `users/{uid}` is created with role "runner".
/// - The profile document is observed live, so a role change made by an admin (or in the Firebase
///   console) switches the tabs immediately.
/// - `lastActiveAt` is refreshed when the app becomes active (at most every 5 minutes).
@Observable
final class AuthService {
    enum State: Equatable { case loading, signedOut, signedIn }

    private(set) var state: State = .loading
    private(set) var uid: String?
    private(set) var profile: UserProfile?
    private(set) var errorMessage: String?
    private(set) var infoMessage: String?
    private(set) var isWorking = false

    /// Called when the signed-in user changes (uid, or nil on sign-out).
    @ObservationIgnored var onUserChange: ((String?) -> Void)?
    /// Called when the profile document loads or changes (e.g. role edited by an admin).
    @ObservationIgnored var onProfileChange: ((UserProfile?) -> Void)?
    @ObservationIgnored private var authHandle: AuthStateDidChangeListenerHandle?
    @ObservationIgnored private var profileListener: ListenerRegistration?
    @ObservationIgnored private var lastTouch: Date?
    @ObservationIgnored private var pendingName: String?

    private var db: Firestore { Firestore.firestore() }

    var email: String? { profile?.email ?? Auth.auth().currentUser?.email }

    func start() {
        guard authHandle == nil else { return }
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.handle(user)
        }
    }

    // MARK: Actions

    func signUp(name: String, email: String, password: String) async {
        await run {
            self.pendingName = name
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            let change = result.user.createProfileChangeRequest()
            change.displayName = name
            try? await change.commitChanges()
            try self.createProfile(uid: result.user.uid, name: name, email: email)
        }
    }

    func signIn(email: String, password: String) async {
        await run { _ = try await Auth.auth().signIn(withEmail: email, password: password) }
    }

    func sendPasswordReset(email: String) async {
        await run {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            self.infoMessage = "Password reset email sent to \(email)."
        }
    }

    func signOut() {
        try? Auth.auth().signOut()
    }

    /// Updates `lastActiveAt` (called when the app becomes active).
    func touchLastActive() {
        guard let uid, Date.now.timeIntervalSince(lastTouch ?? .distantPast) > 300 else { return }
        lastTouch = .now
        db.collection("users").document(uid).updateData(["lastActiveAt": FieldValue.serverTimestamp()])
    }

    func clearMessages() {
        errorMessage = nil
        infoMessage = nil
    }

    // MARK: Private

    private func handle(_ user: User?) {
        profileListener?.remove()
        profileListener = nil
        guard let user else {
            let wasSignedIn = uid != nil
            uid = nil
            profile = nil
            state = .signedOut
            if wasSignedIn { onUserChange?(nil) }
            return
        }
        let changed = uid != user.uid
        uid = user.uid
        if changed { onUserChange?(user.uid) }
        state = .signedIn
        lastTouch = nil
        touchLastActive()

        // Live profile: role changes apply immediately. Missing doc (e.g. created in the console) → create it.
        profileListener = db.collection("users").document(user.uid).addSnapshotListener { [weak self] snapshot, _ in
            guard let self, let snapshot else { return }
            if snapshot.exists {
                self.profile = try? snapshot.data(as: UserProfile.self)
                self.onProfileChange?(self.profile)
            } else if !snapshot.metadata.isFromCache {
                try? self.createProfile(uid: user.uid,
                                        name: self.pendingName ?? user.displayName ?? user.email?.components(separatedBy: "@").first ?? "Runner",
                                        email: user.email ?? "")
            }
        }
    }

    /// New accounts are always runners (firestore.rules rejects anything else on create).
    private func createProfile(uid: String, name: String, email: String) throws {
        let profile = UserProfile(displayName: name, email: email, role: .runner,
                                  createdAt: .now, lastActiveAt: .now, linkedBusinessId: nil)
        try db.collection("users").document(uid).setData(from: profile, merge: true)
    }

    private func run(_ work: @escaping () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        infoMessage = nil
        do {
            try await work()
        } catch {
            errorMessage = Self.friendly(error)
        }
        isWorking = false
    }

    private static func friendly(_ error: Error) -> String {
        print("AuthService error: \(error as NSError)")   // full details in the Xcode console
        let code = AuthErrorCode(rawValue: (error as NSError).code)
        if code == .internalError, let detail = serverMessage(error) {
            return explain(serverMessage: detail)
        }
        switch code {
        case .wrongPassword, .invalidCredential, .userNotFound: return "Email or password is incorrect."
        case .emailAlreadyInUse: return "An account with this email already exists. Try signing in."
        case .weakPassword: return "Use at least 6 characters for your password."
        case .invalidEmail: return "That email address doesn't look right."
        case .networkError: return "No connection. Check your internet and try again."
        case .operationNotAllowed: return "Email sign-in isn't enabled in Firebase yet (see README)."
        default: return error.localizedDescription
        }
    }

    /// FirebaseAuth wraps the server's real reason ("CONFIGURATION_NOT_FOUND", "API key not valid", …)
    /// inside a generic "internal error". Dig it out.
    private static func serverMessage(_ error: Error) -> String? {
        let nsError = error as NSError
        let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        let response = underlying?.userInfo["FIRAuthErrorUserInfoDeserializedResponseKey"] as? [String: Any]
        if let message = response?["message"] as? String { return message }
        if let data = underlying?.userInfo["FIRAuthErrorUserInfoDataKey"] as? Data,
           let text = String(data: data, encoding: .utf8) { return text }
        return underlying?.localizedDescription
    }

    /// Plain-English fixes for the usual setup problems behind "An internal error has occurred".
    private static func explain(serverMessage message: String) -> String {
        let m = message.uppercased()
        if m.contains("CONFIGURATION_NOT_FOUND") {
            return "Firebase Authentication isn't set up yet. In the Firebase console open Authentication, click Get started, then enable Email/Password. (\(message))"
        }
        if m.contains("API_KEY") || m.contains("API KEY") || m.contains("BLOCKED") || m.contains("PERMISSION_DENIED") {
            return "The Firebase API key is blocked or restricted for Authentication. Check the iOS key in Google Cloud → APIs & Services → Credentials, and that Identity Toolkit API is enabled. (\(message))"
        }
        if m.contains("PASSWORD_DOES_NOT_MEET_REQUIREMENTS") {
            return "That password doesn't meet this project's password policy. Try a longer one with letters and numbers."
        }
        return "Sign-in failed: \(message)"
    }
}
