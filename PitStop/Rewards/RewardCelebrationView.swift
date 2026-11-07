import SwiftUI

/// Full-screen celebration after a check-in: the reward (or why it stayed locked) and the
/// anti-cheat verdict with its reasons.
struct RewardCelebrationView: View {
    let event: CheckInEvent
    let onDone: () -> Void

    @State private var appeared = false
    @State private var stampLanded = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture(perform: onDone)

            VStack(spacing: 18) {
                ZStack {
                    if event.verification.passed {
                        ForEach(0..<10, id: \.self) { i in
                            Image(systemName: ["sparkle", "star.fill", "circle.fill"][i % 3])
                                .font(.system(size: CGFloat(10 + (i % 3) * 4)))
                                .foregroundStyle([Theme.sun, Theme.coral, Theme.lime, Theme.sky][i % 4])
                                .offset(x: appeared ? cos(Double(i) * .pi / 5) * 95 : 0,
                                        y: appeared ? sin(Double(i) * .pi / 5) * 95 : 0)
                                .opacity(appeared ? 0 : 1)
                        }
                    }
                    Image(systemName: icon)
                        .font(.system(size: 46, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 104, height: 104)
                        .background((event.verification.passed ? Theme.coral : Color.gray).gradient, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 4))
                        .scaleEffect(appeared ? 1 : 0.4)
                        .shadow(color: Theme.coral.opacity(0.5), radius: 20)
                }
                .frame(height: 150)

                VStack(spacing: 6) {
                    Text(event.verification.passed ? "Checked in!" : "Check-in not verified")
                        .font(.title.weight(.heavy))
                    Text(event.destination.name).font(.headline).foregroundStyle(.secondary)
                    if event.isFirstVisit && event.verification.passed {
                        Label("First visit: new place in My Places", systemImage: "mappin.and.ellipse")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.lime)
                    }
                }

                if event.earnedStamp {
                    VStack(spacing: 6) {
                        PassportStampView(name: event.destination.name, category: event.destination.category,
                                          date: .now, seed: event.destination.id, size: 112)
                            .scaleEffect(stampLanded ? 1 : 2.2)
                            .opacity(stampLanded ? 1 : 0)
                        Text("New passport stamp!")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.coral)
                    }
                }

                if let reward = event.reward {
                    rewardTicket(reward, unlocked: true)
                } else if let locked = event.lockedReward {
                    rewardTicket(locked, unlocked: false)
                }

                verificationBox

                Button(action: onDone) {
                    Text("Done").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .padding(24)
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.45)) { appeared = true }
        }
        .task {
            // The stamp "thunks" down onto the card a moment later, with a heavy haptic.
            guard event.earnedStamp else { return }
            try? await Task.sleep(for: .milliseconds(550))
            withAnimation(.spring(duration: 0.35, bounce: 0.3)) { stampLanded = true }
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
    }

    private var icon: String {
        if !event.verification.passed { return "xmark.shield.fill" }
        return event.reward != nil ? "gift.fill" : "flag.checkered"
    }

    private func rewardTicket(_ text: String, unlocked: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: unlocked ? "gift.fill" : "lock.fill").font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(unlocked ? "Reward unlocked" : "Reward locked")
                    .font(.caption.weight(.heavy)).textCase(.uppercase).opacity(0.75)
                Text(text).font(.headline)
                if unlocked {
                    Text("Show this in Rewards at the counter").font(.caption).opacity(0.75)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(unlocked ? .black.opacity(0.85) : .secondary)
        .padding(14)
        .background(unlocked ? AnyShapeStyle(Theme.sun) : AnyShapeStyle(Color.secondary.opacity(0.15)),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var verificationBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(event.verification.passed ? "Run verified" : "Run flagged by anti-cheat",
                  systemImage: event.verification.passed ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(event.verification.passed ? Theme.lime : .red)
            ForEach(event.verification.reasons, id: \.self) { reason in
                Label(reason, systemImage: "xmark.circle").font(.caption)
            }
            ForEach(event.verification.notes, id: \.self) { note in
                Label(note, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
