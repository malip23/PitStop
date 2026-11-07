import SwiftUI

/// Floating bottom card with live run stats and Start / Pause / Resume / End controls.
struct RunStatsCard: View {
    @Environment(AppState.self) private var app
    /// Opens the "Plan your run" sheet.
    var onPlan: () -> Void = {}

    var body: some View {
        let run = app.run
        MaterialCard {
            VStack(alignment: .leading, spacing: 14) {
                // TimelineView redraws once a second so elapsed time ticks without a Timer.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(alignment: .firstTextBaseline) {
                        Text(Format.duration(run.elapsed(at: context.date)))
                            .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText())
                        Spacer()
                        statusBadge
                    }
                }

                HStack(spacing: 12) {
                    StatTile(title: "Distance", value: Format.distance(run.distanceMeters),
                             symbol: "point.topleft.down.to.point.bottomright.curvepath")
                    StatTile(title: "Pace", value: Format.pace(secondsPerMeter: run.currentPace),
                             unit: Format.paceUnit, symbol: "speedometer")
                    StatTile(title: "Heart", value: run.heartRate.map { "\(Int($0))" } ?? "--",
                             unit: run.heartRate == nil ? nil : "bpm",
                             symbol: "heart.fill", tint: .red, dimmed: run.heartRate == nil)
                }

                goalProgress

                controls
            }
        }
        .animation(.snappy, value: run.state)
    }

    /// Progress bar toward the plan's goal distance ("1.2 of 3.0 mi").
    @ViewBuilder private var goalProgress: some View {
        if let progress = app.run.goalProgress, let target = app.run.targetDistance, let plan = app.activePlan {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress)
                    .tint(Color.accentColor)
                HStack {
                    Label(plan.activity.displayName, systemImage: plan.activity.symbol)
                    Text("·")
                    Text(plan.shape.displayName)
                    Spacer()
                    Text("\(Format.distance(app.run.distanceMeters)) of \(Format.distance(target))")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var statusBadge: some View {
        switch app.run.state {
        case .idle:
            Text("Ready").badgeStyle(.secondary)
        case .running:
            Label("Running", systemImage: "circle.fill").badgeStyle(.green)
                .symbolEffect(.pulse)
        case .paused:
            Text("Paused").badgeStyle(.orange)
        case .finished:
            Text("Finished").badgeStyle(.blue)
        }
    }

    @ViewBuilder private var controls: some View {
        switch app.run.state {
        case .idle:
            Button(action: onPlan) {
                Label("Plan Run", systemImage: "figure.run").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!app.location.isAuthorized)
            .sensoryFeedback(.start, trigger: app.run.state)

        case .running, .paused:
            HStack(spacing: 12) {
                if app.run.state == .running {
                    Button { app.pauseRun() } label: {
                        Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button { app.resumeRun() } label: {
                        Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button(role: .destructive) { app.endRun() } label: {
                    Label("End", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .sensoryFeedback(.impact, trigger: app.run.state)

        case .finished:
            Button { app.resetRun() } label: {
                Label("Done", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

private extension View {
    /// Small capsule label used for the run status.
    func badgeStyle(_ color: Color) -> some View {
        self.font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}
