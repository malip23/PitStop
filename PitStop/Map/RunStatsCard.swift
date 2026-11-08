import SwiftUI

/// Bottom run controls, compact by default so the map stays the focus.
///
/// - **Idle:** one row of buttons (Plan Run, or Edit plan + Start).
/// - **Running / paused:** a slim strip with time · distance · pace · distance left, a pause/resume
///   button, and a thin goal-progress line. Tap the strip to expand the full card.
/// - **Finished:** the full summary with the anti-cheat verdict and Done.
struct RunStatsCard: View {
    @Environment(AppState.self) private var app
    /// Opens the "Plan your run" sheet.
    var onPlan: () -> Void = {}

    @State private var expanded = false
    @State private var shareRun: RunRecord?

    var body: some View {
        Group {
            switch app.run.state {
            case .idle:
                MaterialCard(padding: 10) { idleControls }
            case .running, .paused:
                if expanded { fullCard } else { strip }
            case .finished:
                fullCard
            }
        }
        .animation(.snappy, value: app.run.state)
        .animation(.snappy, value: expanded)
    }

    // MARK: Compact strip

    private var strip: some View {
        let run = app.run
        return MaterialCard(padding: 10) {
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        StripStat(value: Format.duration(run.elapsed(at: context.date)), label: "Time", emphasized: true)
                    }
                    StripStat(value: Format.distance(run.distanceMeters), label: "Dist")
                    StripStat(value: Format.pace(secondsPerMeter: run.currentPace), label: Format.paceUnit)
                    if let left = distanceLeft {
                        StripStat(value: Format.distance(left), label: "Left", tint: Theme.coral)
                    }
                    Spacer(minLength: 0)
                    pauseResumeButtons
                }
                if let progress = run.goalProgress {
                    ProgressView(value: progress).tint(Theme.coral).scaleEffect(y: 0.6)
                }
                checkInProgress
            }
            .contentShape(Rectangle())
            .onTapGesture { expanded = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint("Double-tap to show all stats")
    }

    @ViewBuilder private var pauseResumeButtons: some View {
        if app.run.state == .running {
            CircleButton(symbol: "pause.fill", label: "Pause") { app.pauseRun() }
        } else {
            CircleButton(symbol: "play.fill", label: "Resume", prominent: true) { app.resumeRun() }
            CircleButton(symbol: "stop.fill", label: "End run", tint: .red) { app.endRun() }
        }
    }

    // MARK: Full card (expanded or finished)

    private var fullCard: some View {
        let run = app.run
        return MaterialCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(alignment: .firstTextBaseline) {
                        Text(Format.duration(run.elapsed(at: context.date)))
                            .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
                            .contentTransition(.numericText())
                        Spacer()
                        statusBadge
                        if run.isActive {
                            Button { expanded = false } label: {
                                Image(systemName: "chevron.down").font(.subheadline.weight(.bold))
                            }
                            .frame(width: 44, height: 44)
                            .accessibilityLabel("Collapse stats")
                        }
                    }
                }

                HStack(spacing: 12) {
                    StatTile(title: "Distance", value: Format.distance(run.distanceMeters),
                             symbol: "point.topleft.down.to.point.bottomright.curvepath")
                    StatTile(title: "Pace", value: Format.pace(secondsPerMeter: run.currentPace),
                             unit: Format.paceUnit, symbol: "speedometer")
                    StatTile(title: "Left", value: distanceLeft.map { Format.distance($0) } ?? "--",
                             symbol: "flag.checkered", tint: Theme.coral, dimmed: distanceLeft == nil)
                }

                goalProgress
                checkInProgress
                finishedVerdict
                fullControls
            }
        }
    }

    /// Distance still to go: the rest of the route when navigating, otherwise what's left of the goal.
    private var distanceLeft: Double? {
        if app.navigation.isNavigating { return app.navigation.remainingDistance }
        guard let target = app.run.targetDistance else { return nil }
        return max(0, target - app.run.distanceMeters)
    }

    /// Progress bar toward the plan's goal distance ("1.2 of 3.0 mi").
    @ViewBuilder private var goalProgress: some View {
        if let progress = app.run.goalProgress, let target = app.run.targetDistance, let plan = app.activePlan {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress).tint(Theme.coral)
                HStack {
                    Label(plan.activity.displayName, systemImage: plan.activity.symbol)
                    Text("·")
                    Text(plan.shape.displayName)
                    Spacer()
                    Text("\(Format.distance(app.run.distanceMeters)) of \(Format.distance(target))").monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// "Checking in…" ring while the runner waits the 10 seconds at the destination.
    @ViewBuilder private var checkInProgress: some View {
        if app.checkIn.enteredAt != nil, !app.checkIn.isCheckedIn {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                HStack(spacing: 8) {
                    ProgressView(value: app.checkIn.dwellProgress).progressViewStyle(.circular).tint(Theme.lime)
                    Text("Checking in at \(app.checkIn.target?.name ?? "destination"). Stay here…")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
            }
        } else if app.checkIn.isCheckedIn {
            Label("Checked in at \(app.checkIn.target?.name ?? "destination")", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.lime)
                .lineLimit(1)
        }
    }

    /// After the run: the anti-cheat verdict.
    @ViewBuilder private var finishedVerdict: some View {
        if app.run.state == .finished, let record = app.lastFinishedRun {
            VStack(alignment: .leading, spacing: 4) {
                Label(record.verification.passed ? "Verified run" : "Not verified",
                      systemImage: record.verification.passed ? "checkmark.shield.fill" : "xmark.shield.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(record.verification.passed ? Theme.lime : .red)
                ForEach(record.verification.reasons, id: \.self) {
                    Text("• \($0)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var statusBadge: some View {
        switch app.run.state {
        case .idle: Text("Ready").badgeStyle(.secondary)
        case .running: Label("Running", systemImage: "circle.fill").badgeStyle(.green).symbolEffect(.pulse)
        case .paused: Text("Paused").badgeStyle(.orange)
        case .finished: Text("Finished").badgeStyle(.blue)
        }
    }

    // MARK: Controls

    @ViewBuilder private var idleControls: some View {
        if app.pendingPlan != nil || app.destination != nil {
            let plan = app.planForRouting
            HStack(spacing: 10) {
                Button(action: onPlan) {
                    Label("Edit plan", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button { app.startPlannedRun() } label: {
                    Label("Start \(plan.activity.displayName)", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
            .disabled(!app.location.isAuthorized)
            .sensoryFeedback(.start, trigger: app.run.state)
        } else {
            Button(action: onPlan) {
                Label("Plan Run", systemImage: "figure.run").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!app.location.isAuthorized)
            .sensoryFeedback(.start, trigger: app.run.state)
        }
    }

    @ViewBuilder private var fullControls: some View {
        switch app.run.state {
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
            HStack(spacing: 12) {
                if let record = app.lastFinishedRun, record.distanceMeters > 20 {
                    Button { shareRun = record } label: {
                        Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    expanded = false
                    app.resetRun()
                } label: {
                    Label("Done", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
            .sheet(item: $shareRun) { ShareRunSheet(run: $0) }
        case .idle:
            EmptyView()
        }
    }
}

/// One value in the compact strip ("2.31 mi" over "Dist").
private struct StripStat: View {
    let value: String
    let label: String
    var emphasized = false
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font((emphasized ? Font.headline : Font.subheadline).weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 44 pt round icon button used in the compact strip.
private struct CircleButton: View {
    let symbol: String
    let label: String
    var tint: Color = Theme.coral
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(prominent ? .white : tint)
                .frame(width: 44, height: 44)
                .background(prominent ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.15)), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
