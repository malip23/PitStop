import FirebaseFirestore
import SwiftUI

/// Live list of recent check-ins at one business (Firestore `visits`, owner/admin only).
/// Shows only what a business may see: time and whether the visit was verified.
struct RecentVisitsList: View {
    let businessID: String
    @State private var visits: [Visit]?
    @State private var listener: ListenerRegistration?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let visits {
                if visits.isEmpty {
                    Text("No check-ins yet.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Recent check-ins").font(.subheadline.weight(.semibold))
                    ForEach(visits.prefix(5)) { visit in
                        HStack(spacing: 8) {
                            Image(systemName: visit.verified ? "checkmark.shield.fill" : "xmark.shield.fill")
                                .foregroundStyle(visit.verified ? Theme.lime : .red)
                            Text(visit.timestamp.formatted(date: .abbreviated, time: .shortened))
                            Spacer()
                            Text(visit.verified ? "Verified" : "Not verified")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .onAppear {
            listener = Visit.listen(businessId: businessID) { visits = $0 }
        }
        .onDisappear {
            listener?.remove()
            listener = nil
        }
    }
}
