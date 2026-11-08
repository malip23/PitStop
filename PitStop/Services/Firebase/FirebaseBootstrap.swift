import FirebaseCore
import FirebaseFirestore

/// One-time Firebase setup, run at app launch before anything touches Firebase.
enum FirebaseBootstrap {
    static func configure() {
        guard FirebaseApp.app() == nil else { return }
        FirebaseApp.configure()   // reads GoogleService-Info.plist

        // Offline persistence: reads come from the on-device cache and writes queue up while offline
        // (e.g. flaky venue Wi-Fi), then sync automatically.
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings(sizeBytes: NSNumber(value: 100 * 1024 * 1024))
        Firestore.firestore().settings = settings
    }
}
