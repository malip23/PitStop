import SwiftUI

/// "Plan your run": activity, goal (distance or time), route shape, and "surprise me".
/// Opens with the user's last choices.
struct PlanRunSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var plan = RunPlan()
    @State private var didLoad = false
    @State private var showResults = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    activitySection
                    goalSection
                    shapeSection
                    surpriseSection
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) { actionButtons }
            .navigationDestination(isPresented: $showResults) {
                DestinationListView(plan: plan) { dismiss() }
            }
            .navigationTitle("Plan your \(plan.activity.displayName.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                plan = app.pendingPlan ?? app.planStore.lastPlan
            }
            .sensoryFeedback(.selection, trigger: plan.activity)
            .sensoryFeedback(.selection, trigger: plan.shape)
        }
    }

    // MARK: Sections

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Activity")
            HStack(spacing: 10) {
                ForEach(Activity.allCases) { activity in
                    ChoiceTile(title: activity.displayName, symbol: activity.symbol,
                               isSelected: plan.activity == activity) {
                        plan.activity = activity
                    }
                }
            }
        }
    }

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Goal")
            Picker("Goal type", selection: $plan.goalType) {
                ForEach(RunPlan.GoalType.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                switch plan.goalType {
                case .distance:
                    Text(String(format: "%.1f mi", plan.goalMiles))
                        .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                    Slider(value: $plan.goalMiles, in: RunPlan.distanceRange, step: 0.5) {
                        Text("Distance")
                    } minimumValueLabel: { Text("1") } maximumValueLabel: { Text("10") }
                    Text("About \(Format.minutes(plan.goalMiles * Units.metersPerMile * pace.secondsPerMeter)) at \(paceText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                case .time:
                    Text("\(Int(plan.goalMinutes)) min")
                        .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                    Slider(value: $plan.goalMinutes, in: RunPlan.minutesRange, step: 5) {
                        Text("Time")
                    } minimumValueLabel: { Text("15") } maximumValueLabel: { Text("90") }
                    Text("≈ \(String(format: "%.1f mi", target / Units.metersPerMile)) at \(paceText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .animation(.snappy, value: plan.goalMiles)
            .animation(.snappy, value: plan.goalMinutes)
        }
    }

    private var shapeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Route shape")
            ForEach(RunPlan.RouteShape.allCases) { shape in
                Button {
                    plan.shape = shape
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: shape.symbol)
                            .font(.title2)
                            .foregroundStyle(plan.shape == shape ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shape.displayName).font(.headline).foregroundStyle(.primary)
                            Text(shape.detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: plan.shape == shape ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(plan.shape == shape ? Color.accentColor : .secondary)
                    }
                    .padding(14)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: plan.shape == shape ? 2 : 0))
                }
                .buttonStyle(.plain)
            }
            Text(destinationHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var surpriseSection: some View {
        Toggle(isOn: $plan.surpriseMe) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Surprise me").font(.headline)
                    Text("We'll pick a destination that fits your goal").font(.subheadline).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "dice.fill").foregroundStyle(Color.accentColor)
            }
        }
        .tint(Color.accentColor)
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var actionButtons: some View {
        VStack(spacing: 8) {
            Button {
                app.findDestinations(for: plan)
                showResults = true
            } label: {
                Label(plan.surpriseMe ? "Surprise me" : "Find destinations",
                      systemImage: plan.surpriseMe ? "dice.fill" : "mappin.and.ellipse")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)

            Button("Start without a destination") {
                app.startRun(with: plan)
                dismiss()
            }
            .font(.subheadline.weight(.medium))
        }
        .controlSize(.large)
        .padding()
        .background(.bar)
        .disabled(!app.location.isAuthorized || app.currentLocation == nil)
    }

    // MARK: Derived values

    private var pace: (secondsPerMeter: Double, source: RunPlanStore.PaceSource) {
        app.planStore.pace(for: plan.activity)
    }

    private var target: Double { plan.targetDistance(secondsPerMeter: pace.secondsPerMeter) }

    private var paceText: String {
        let value = "\(Format.pace(secondsPerMeter: pace.secondsPerMeter)) \(Format.paceUnit)"
        return pace.source == .history ? "your usual \(value)" : "\(value) (default pace)"
    }

    private var destinationHint: String {
        let range = plan.destinationRange(target: target)
        return "Destinations \(String(format: "%.1f–%.1f mi", range.lowerBound / Units.metersPerMile, range.upperBound / Units.metersPerMile)) away fit this goal."
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.title3.weight(.bold))
    }
}

/// Big tappable tile for picking the activity.
private struct ChoiceTile: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.title2)
                Text(title).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(isSelected ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color(.secondarySystemBackground)),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: isSelected)
    }
}
