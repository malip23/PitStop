import SwiftData
import SwiftUI

/// Every saved run, newest first. Tap one to see its route and stats.
struct RunHistoryView: View {
    @Environment(AppState.self) private var app
    @Query(sort: \RunRecord.date, order: .reverse) private var runs: [RunRecord]

    var body: some View {
        List {
            ForEach(runs) { run in
                NavigationLink {
                    RunDetailView(run: run)
                } label: {
                    RunHistoryRow(run: run)
                }
            }
            .onDelete { offsets in
                for index in offsets { app.history.delete(runs[index]) }
            }
        }
        .overlay {
            if runs.isEmpty {
                ContentUnavailableView("No runs yet", systemImage: "figure.run",
                                       description: Text("Finished runs are saved here with their route and stats."))
            }
        }
        .navigationTitle("Run History")
    }
}

private struct RunHistoryRow: View {
    let run: RunRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: run.activity.symbol)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Theme.coral.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(run.destinationName ?? "Free \(run.activity.displayName.lowercased())")
                    .font(.body.weight(.semibold)).lineLimit(1)
                Text("\(Format.distance(run.distanceMeters)) · \(Format.duration(run.durationSeconds)) · \(Format.pace(secondsPerMeter: run.averagePaceSecondsPerMeter)) \(Format.paceUnit)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Text(run.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            VerificationBadge(result: run.verification)
        }
    }
}

/// ✓ / ✗ shield for a run's anti-cheat verdict.
struct VerificationBadge: View {
    let result: VerificationResult

    var body: some View {
        Image(systemName: result.passed ? "checkmark.shield.fill" : "xmark.shield.fill")
            .font(.title3)
            .foregroundStyle(result.passed ? Theme.lime : .red)
            .accessibilityLabel(result.passed ? "Verified" : "Not verified")
    }
}
