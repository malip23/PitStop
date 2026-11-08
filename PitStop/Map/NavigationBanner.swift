import SwiftUI

/// One compact row while navigating: turn icon, instruction, distance to the turn, and a follow toggle.
/// Tap to expand remaining distance and ETA. Turns orange with Reroute when off route.
struct NavigationBanner: View {
    @Environment(AppState.self) private var app
    @Binding var followRunner: Bool
    @State private var expanded = false

    var body: some View {
        let nav = app.navigation
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if nav.isOffRoute {
                    Image(systemName: "exclamationmark.triangle.fill").font(.title3)
                    Text("Off route").font(.subheadline.weight(.bold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Button {
                        app.reroute()
                    } label: {
                        if app.isRerouting { ProgressView().tint(.orange) } else { Text("Reroute").font(.subheadline.weight(.bold)) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.orange)
                    .frame(minHeight: 44)
                } else {
                    Image(systemName: nav.hasArrived ? "flag.checkered" : (nav.nextStep?.symbol ?? "arrow.up"))
                        .font(.title3.weight(.bold))
                        .frame(width: 30)
                    Text(nav.hasArrived ? "You've arrived" : (nav.nextStep?.instruction ?? "Continue on the route"))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(expanded ? 2 : 1)
                    Spacer(minLength: 4)
                    if !nav.hasArrived {
                        Text(Format.shortDistance(nav.distanceToNextStep))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .contentTransition(.numericText())
                    }
                }
                Button {
                    followRunner.toggle()
                } label: {
                    Image(systemName: followRunner ? "location.north.line.fill" : "location.north.line")
                        .font(.subheadline.weight(.bold))
                }
                .frame(width: 44, height: 44)
                .accessibilityLabel(followRunner ? "Stop following" : "Follow me")
            }
            if expanded {
                HStack {
                    Label("\(Format.distance(nav.remainingDistance)) left", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    Spacer()
                    Label("ETA \(eta)", systemImage: "clock")
                }
                .font(.caption.weight(.semibold).monospacedDigit())
                .opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .frame(minHeight: 56)
        .background((nav.isOffRoute ? Color.orange : Theme.coralDeep).gradient,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
        .animation(.snappy, value: nav.isOffRoute)
        .accessibilityElement(children: .contain)
    }

    /// Clock time of arrival: remaining distance at current pace (or the plan's usual pace).
    private var eta: String {
        let pace = app.run.currentPace
            ?? app.planStore.pace(for: (app.activePlan ?? app.planForRouting).activity).secondsPerMeter
        let arrival = Date.now.addingTimeInterval(app.navigation.remainingDistance * pace)
        return "\(arrival.formatted(date: .omitted, time: .shortened)) · \(Format.minutes(app.navigation.remainingDistance * pace))"
    }
}
