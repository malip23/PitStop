import SwiftUI

/// Top banner while navigating: next instruction and distance to it, then remaining distance and ETA.
/// Turns orange with a Reroute button when the runner is off route.
struct NavigationBanner: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let nav = app.navigation
        VStack(alignment: .leading, spacing: 10) {
            if nav.isOffRoute {
                offRoute
            } else if nav.hasArrived {
                Label("You've arrived!", systemImage: "flag.checkered")
                    .font(.title3.weight(.bold))
            } else {
                HStack(spacing: 14) {
                    Image(systemName: nav.nextStep?.symbol ?? "arrow.up")
                        .font(.system(size: 30, weight: .bold))
                        .frame(width: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Format.shortDistance(nav.distanceToNextStep))
                            .font(.title2.weight(.bold).monospacedDigit())
                            .contentTransition(.numericText())
                        Text(nav.nextStep?.instruction ?? "Continue on the route")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
            }

            Divider().overlay(.white.opacity(0.3))

            HStack {
                Label("\(Format.distance(nav.remainingDistance)) left", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                Spacer()
                Label("ETA \(eta)", systemImage: "clock")
            }
            .font(.caption.weight(.semibold).monospacedDigit())
            .opacity(0.9)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background((nav.isOffRoute ? Color.orange : Theme.coralDeep).gradient,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
        .animation(.snappy, value: nav.isOffRoute)
        .animation(.snappy, value: nav.nextStep)
    }

    private var offRoute: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("You're off route").font(.headline)
                Text("More than 40 m from the path").font(.caption).opacity(0.9)
            }
            Spacer()
            Button {
                app.reroute()
            } label: {
                if app.isRerouting {
                    ProgressView().tint(.orange)
                } else {
                    Text("Reroute").font(.subheadline.weight(.bold))
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.orange)
        }
    }

    /// Clock time of arrival: remaining distance at current pace (or the plan's usual pace).
    private var eta: String {
        let pace = app.run.currentPace
            ?? app.planStore.pace(for: (app.activePlan ?? app.planForRouting).activity).secondsPerMeter
        let arrival = Date.now.addingTimeInterval(app.navigation.remainingDistance * pace)
        return "\(arrival.formatted(date: .omitted, time: .shortened)) · \(Format.minutes(app.navigation.remainingDistance * pace))"
    }
}
