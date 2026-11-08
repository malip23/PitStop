import Charts
import FirebaseFirestore
import SwiftUI

/// "Is PitStop working for me?": the business owner's impact view.
///
/// - **Check-ins over time:** single-series bars (today by hour, or the last 7 days by day), with the
///   business's Off-Peak windows shaded behind them, so you can see visits landing in quiet hours.
/// - **Two headline numbers:** check-ins during Off-Peak, and offer acceptance rate.
/// - **Offer funnel:** offers shown → accepted → verified visits, with conversion.
///
/// Data: `visits` for this business (live) and its `quests` (windows + offer stats). Only verified
/// visits are counted as check-ins.
struct BusinessInsightsCard: View {
    enum Range: String, CaseIterable, Identifiable { case today = "Today", week = "7 days"; var id: Self { self } }

    @Environment(AppState.self) private var app
    let business: Business

    @State private var range: Range = .today
    @State private var visits: [Visit] = []
    @State private var listener: ListenerRegistration?
    @State private var selectedDate: Date?
    @State private var isGenerating = false
    @State private var generateError: String?

    var body: some View {
        let interval = dateInterval
        let shown = visits.filter { $0.verified && interval.contains($0.timestamp) }
        let windows = quests.map(\.window).filter { $0.intersects(interval) }
        let offPeak = shown.filter { visit in windows.contains { $0.contains(visit.timestamp) } }
        let stats = funnel(in: interval, verifiedVisits: shown.filter { $0.questId != nil }.count)

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Impact", systemImage: "chart.bar.xaxis").font(.headline)
                Spacer()
                Picker("Range", selection: $range) {
                    ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            // Headline numbers.
            HStack(spacing: 10) {
                headline(value: "\(offPeak.count)",
                         label: "Check-ins during Off-Peak",
                         detail: shown.isEmpty ? "No check-ins yet" : "\(Int((Double(offPeak.count) / Double(shown.count) * 100).rounded()))% of \(shown.count) total")
                headline(value: stats.shown == 0 ? "–" : "\(Int((Double(stats.accepted) / Double(stats.shown) * 100).rounded()))%",
                         label: "Offer acceptance",
                         detail: "\(stats.accepted) of \(stats.shown) offers")
            }

            checkInsChart(visits: shown, windows: windows, interval: interval)

            funnelChart(stats)

            if visits.contains(where: { $0.isSample == true }) {
                Label("Includes sample data", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if business.isMock {
                sampleButton
            }
        }
        .onAppear {
            listener = Visit.listen(businessId: business.id) { visits = $0 ?? [] }
        }
        .onDisappear {
            listener?.remove()
            listener = nil
        }
        .onChange(of: range) { _, _ in selectedDate = nil }
    }

    // MARK: Check-ins chart

    private func checkInsChart(visits: [Visit], windows: [DateInterval], interval: DateInterval) -> some View {
        let unit: Calendar.Component = range == .today ? .hour : .day
        let buckets = Dictionary(grouping: visits) { Calendar.current.dateInterval(of: unit, for: $0.timestamp)!.start }
            .map { (start: $0.key, count: $0.value.count) }
            .sorted { $0.start < $1.start }
        let selected = selectedDate.flatMap { date in
            buckets.first { Calendar.current.isDate($0.start, equalTo: date, toGranularity: unit) }
        }

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Verified check-ins").font(.subheadline.weight(.semibold))
                Spacer()
                RoundedRectangle(cornerRadius: 2).fill(Theme.sun.opacity(0.35)).frame(width: 14, height: 10)
                Text("Off-Peak").font(.caption).foregroundStyle(.secondary)
            }

            Chart {
                // Off-Peak windows: shaded background bands (context, not a data series).
                ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                    RectangleMark(xStart: .value("Start", max(window.start, interval.start)),
                                  xEnd: .value("End", min(window.end, interval.end)))
                        .foregroundStyle(Theme.sun.opacity(0.22))
                        .accessibilityHidden(true)
                }
                ForEach(buckets, id: \.start) { bucket in
                    BarMark(x: .value(range == .today ? "Hour" : "Day", bucket.start, unit: unit),
                            y: .value("Check-ins", bucket.count), width: .ratio(0.6))
                        .foregroundStyle(Theme.coral)
                        .cornerRadius(4)
                        .opacity(selected == nil || selected?.start == bucket.start ? 1 : 0.45)
                        .accessibilityLabel(bucket.start.formatted(range == .today ? .dateTime.hour() : .dateTime.weekday(.abbreviated)))
                        .accessibilityValue("\(bucket.count) check-in\(bucket.count == 1 ? "" : "s")")
                }
                if let selected {
                    RuleMark(x: .value("Selected", selected.start, unit: unit))
                        .foregroundStyle(.secondary.opacity(0.4))
                        .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit, y: .disabled)) {
                            Text("\(selected.start.formatted(range == .today ? .dateTime.hour() : .dateTime.weekday(.abbreviated).day())) · \(selected.count)")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(.regularMaterial, in: Capsule())
                        }
                }
            }
            .chartXScale(domain: interval.start...interval.end)
            .chartXSelection(value: $selectedDate)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                    AxisValueLabel().font(.caption2)
                }
            }
            .chartXAxis {
                if range == .today {
                    AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                        AxisValueLabel(format: .dateTime.hour()).font(.caption2)
                    }
                } else {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow)).font(.caption2)
                    }
                }
            }
            .frame(height: 150)
            .overlay {
                if visits.isEmpty {
                    Text(range == .today ? "No check-ins today yet" : "No check-ins this week yet")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Funnel

    private struct Funnel { let shown: Int; let accepted: Int; let visited: Int }

    private func funnel(in interval: DateInterval, verifiedVisits: Int) -> Funnel {
        let inRange = quests.filter { $0.window.intersects(interval) }
        return Funnel(shown: inRange.reduce(0) { $0 + ($1.offerStats?.shown ?? 0) },
                      accepted: inRange.reduce(0) { $0 + ($1.offerStats?.accepted ?? 0) },
                      visited: verifiedVisits)
    }

    private func funnelChart(_ f: Funnel) -> some View {
        let steps = [("Shown", f.shown), ("Accepted", f.accepted), ("Visited", f.visited)]
        return VStack(alignment: .leading, spacing: 6) {
            Text("Offer funnel").font(.subheadline.weight(.semibold))
            Chart(steps, id: \.0) { step in
                BarMark(x: .value("Count", step.1), y: .value("Step", step.0), height: .ratio(0.55))
                    .foregroundStyle(Theme.coral)
                    .cornerRadius(4)
                    .annotation(position: .trailing, spacing: 6) {
                        Text(label(for: step, in: f))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(step.0)
                    .accessibilityValue("\(step.1)")
            }
            .chartXAxis(.hidden)
            .chartXScale(domain: 0...max(Double(f.shown), 1) * 1.25)
            .chartYAxis {
                AxisMarks { _ in AxisValueLabel().font(.caption) }
            }
            .frame(height: 96)
        }
    }

    /// "12", "5 · 42%": conversion from the previous step.
    private func label(for step: (String, Int), in f: Funnel) -> String {
        switch step.0 {
        case "Accepted" where f.shown > 0: return "\(step.1) · \(Int((Double(step.1) / Double(f.shown) * 100).rounded()))%"
        case "Visited" where f.accepted > 0: return "\(step.1) · \(Int((Double(step.1) / Double(f.accepted) * 100).rounded()))%"
        default: return "\(step.1)"
        }
    }

    // MARK: Pieces

    private func headline(value: String, label: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.bold).monospacedDigit())
            Text(label).font(.caption.weight(.semibold))
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var sampleButton: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                guard let uid = app.auth.uid else { return }
                isGenerating = true
                generateError = nil
                Task {
                    do { try await SampleDataGenerator.generateWeek(for: business, runnerUid: uid) }
                    catch { generateError = error.localizedDescription }
                    isGenerating = false
                }
            } label: {
                HStack {
                    if isGenerating { ProgressView().controlSize(.small) }
                    Text("Generate sample week (demo)")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isGenerating)
            .frame(minHeight: 44)
            if let generateError {
                Text(generateError).font(.caption).foregroundStyle(.red)
            }
        }
    }

    // MARK: Data

    private var quests: [Quest] {
        app.questStore.quests.filter { $0.businessId == business.id }
    }

    private var dateInterval: DateInterval {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        switch range {
        case .today:
            return DateInterval(start: today, end: calendar.date(byAdding: .day, value: 1, to: today)!)
        case .week:
            return DateInterval(start: calendar.date(byAdding: .day, value: -6, to: today)!,
                                end: calendar.date(byAdding: .day, value: 1, to: today)!)
        }
    }
}
