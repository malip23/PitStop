import ActivityKit
import SwiftUI
import WidgetKit

/// PitStop colors (the widget extension can't see the app's Theme).
private enum Palette {
    static let coral = Color(red: 0.99, green: 0.38, blue: 0.18)
    static let sun = Color(red: 1.00, green: 0.80, blue: 0.20)
    static let lime = Color(red: 0.55, green: 0.90, blue: 0.20)
}

/// The run Live Activity:
/// - Lock Screen: destination, live timer, distance · pace · left, next turn, and a time-limited offer
///   with a shrinking countdown bar.
/// - Dynamic Island: compact (icon + timer, or 🎁 + seconds during an offer), minimal, and expanded.
/// Timers and the countdown bar animate on their own; the app only sends updates when data changes.
struct RunLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.78))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "pitstop://run"))
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(state.distanceText).font(.headline.monospacedDigit())
                    } icon: {
                        Image(systemName: context.attributes.activitySymbol).foregroundStyle(Palette.coral)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedText(state: state).font(.headline.monospacedDigit()).foregroundStyle(Palette.coral)
                }
                DynamicIslandExpandedRegion(.center) {
                    if let name = context.attributes.destinationName {
                        Text(name).font(.caption.weight(.semibold)).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let offer = state.offer {
                        OfferView(offer: offer, compact: true)
                    } else if let instruction = state.nextInstruction {
                        TurnRow(symbol: state.nextSymbol, instruction: instruction, distance: state.nextDistanceText)
                    } else {
                        Text("\(state.paceText)\(state.leftText.map { " · \($0) left" } ?? "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: state.offer == nil ? context.attributes.activitySymbol : "gift.fill")
                    .foregroundStyle(state.offer == nil ? Palette.coral : Palette.sun)
            } compactTrailing: {
                Group {
                    if let offer = state.offer {
                        Text(timerInterval: Date.now...max(offer.deadline, .now), countsDown: true)
                            .foregroundStyle(Palette.sun)
                    } else {
                        ElapsedText(state: state).foregroundStyle(Palette.coral)
                    }
                }
                .font(.caption.weight(.semibold).monospacedDigit())
                .frame(maxWidth: 46)
            } minimal: {
                Image(systemName: state.offer == nil ? context.attributes.activitySymbol : "gift.fill")
                    .foregroundStyle(state.offer == nil ? Palette.coral : Palette.sun)
            }
            .widgetURL(URL(string: "pitstop://run"))
            .keylineTint(Palette.coral)
        }
    }
}

// MARK: - Lock Screen

private struct LockScreenView: View {
    let attributes: RunActivityAttributes
    let state: RunActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: attributes.activitySymbol)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Palette.coral, in: Circle())
                Text(attributes.destinationName.map { "To \($0)" } ?? "PitStop run")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                if state.isPaused {
                    Text("Paused").font(.caption.weight(.bold)).foregroundStyle(Palette.sun)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                ElapsedText(state: state)
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(state.distanceText).font(.headline.monospacedDigit())
                    Text(state.paceText).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    if let left = state.leftText {
                        Text("\(left) left").font(.caption.weight(.semibold)).foregroundStyle(Palette.coral)
                    }
                }
            }

            if let offer = state.offer {
                OfferView(offer: offer, compact: false)
            } else if let instruction = state.nextInstruction {
                TurnRow(symbol: state.nextSymbol, instruction: instruction, distance: state.nextDistanceText)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
    }
}

// MARK: - Pieces

/// Elapsed run time: ticks by itself while running, frozen while paused.
private struct ElapsedText: View {
    let state: RunActivityAttributes.ContentState

    var body: some View {
        if state.isPaused {
            Text(Duration.seconds(state.pausedElapsed).formatted(.time(pattern: state.pausedElapsed >= 3600 ? .hourMinuteSecond : .minuteSecond)))
        } else {
            Text(timerInterval: state.timerStart...Date.distantFuture, countsDown: false)
        }
    }
}

private struct TurnRow: View {
    let symbol: String?
    let instruction: String
    let distance: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol ?? "arrow.up").font(.headline).foregroundStyle(Palette.coral)
            Text(instruction).font(.subheadline.weight(.medium)).lineLimit(1)
            Spacer(minLength: 4)
            if let distance { Text(distance).font(.subheadline.weight(.bold).monospacedDigit()) }
        }
    }
}

/// Time-limited Off-Peak offer with a countdown that shrinks on its own.
private struct OfferView: View {
    let offer: RunActivityAttributes.ContentState.Offer
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "gift.fill").foregroundStyle(Palette.sun)
                Text(offer.reward).font(.subheadline.weight(.bold)).lineLimit(1)
                Spacer(minLength: 4)
                Text(timerInterval: Date.now...max(offer.deadline, .now), countsDown: true)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Palette.sun)
                    .frame(maxWidth: 44, alignment: .trailing)
            }
            if !compact {
                Text("\(offer.businessName) is quiet right now. Open PitStop to accept.")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            ProgressView(timerInterval: offer.deadline.addingTimeInterval(-30)...max(offer.deadline, .now),
                         countsDown: true, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                .tint(Palette.sun)
        }
        .padding(10)
        .background(Palette.sun.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
