import MapKit
import SwiftUI

/// One past run: its route on a map, stats, and the anti-cheat verdict.
struct RunDetailView: View {
    let run: RunRecord
    @State private var sharing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Map(initialPosition: .automatic) {
                    if run.route.count > 1 {
                        GlowingRoute(coordinates: run.route.map(\.coordinate), colors: Theme.completedGradient, lineWidth: 6)
                    }
                    if let start = run.route.first {
                        Annotation("Start", coordinate: start.coordinate) {
                            Circle().fill(Theme.sky).frame(width: 14, height: 14).overlay(Circle().stroke(.white, lineWidth: 3))
                        }
                    }
                    if let point = run.destinationPoint {
                        Annotation(run.destinationName ?? "Destination", coordinate: point.coordinate, anchor: .bottom) {
                            PinBadge.destination.scaleEffect(1.5)
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    stat("Distance", Format.distance(run.distanceMeters), "point.topleft.down.to.point.bottomright.curvepath")
                    stat("Time", Format.duration(run.durationSeconds), "clock")
                    stat("Avg pace", "\(Format.pace(secondsPerMeter: run.averagePaceSecondsPerMeter)) \(Format.paceUnit)", "speedometer")
                    stat("Goal", run.goalText, "target")
                    stat("Shape", run.routeShape.displayName, run.routeShape.symbol)
                    stat("Check-in", run.checkedIn ? "Yes" : "No", run.checkedIn ? "checkmark.circle.fill" : "circle")
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VerificationBadge(result: run.verification)
                        Text(run.verification.passed ? "Verified run" : "Not verified").font(.headline)
                    }
                    ForEach(run.verification.reasons, id: \.self) { Label($0, systemImage: "xmark.circle").font(.subheadline) }
                    ForEach(run.verification.notes, id: \.self) {
                        Label($0, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                    }
                    if let effort = run.effortScore {
                        Label("Effort score \(Int(effort))", systemImage: "flame.fill").font(.subheadline)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(run.destinationName ?? run.date.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button { sharing = true } label: { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Share run")
        }
        .sheet(isPresented: $sharing) { ShareRunSheet(run: run) }
    }

    private func stat(_ title: String, _ value: String, _ symbol: String) -> some View {
        StatTile(title: title, value: value, symbol: symbol, tint: Theme.coral)
    }
}
