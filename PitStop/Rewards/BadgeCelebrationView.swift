import SwiftUI

/// Pops up when a run unlocks milestone badges: each badge springs in with confetti and a haptic.
struct BadgeCelebrationView: View {
    let badges: [BadgeKind]
    let onDone: () -> Void

    @State private var shown = 0
    @State private var burst = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture(perform: onDone)

            VStack(spacing: 20) {
                Text(badges.count == 1 ? "Badge unlocked!" : "\(badges.count) badges unlocked!")
                    .font(.title.weight(.heavy))

                ForEach(Array(badges.enumerated()), id: \.element) { index, kind in
                    HStack(spacing: 14) {
                        ZStack {
                            ForEach(0..<8, id: \.self) { i in
                                Circle()
                                    .fill([Theme.sun, Theme.coral, Theme.lime, Theme.sky][i % 4])
                                    .frame(width: 6, height: 6)
                                    .offset(x: burst ? cos(Double(i) * .pi / 4) * 44 : 0,
                                            y: burst ? sin(Double(i) * .pi / 4) * 44 : 0)
                                    .opacity(burst ? 0 : 1)
                            }
                            Image(systemName: kind.symbol)
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 62, height: 62)
                                .background(kind.color.gradient, in: Circle())
                                .overlay(Circle().stroke(.white, lineWidth: 3))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title).font(.headline)
                            Text(kind.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .scaleEffect(index < shown ? 1 : 0.3)
                    .opacity(index < shown ? 1 : 0)
                }

                Button(action: onDone) {
                    Text("Awesome").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .padding(24)
        }
        .task {
            // Reveal badges one at a time, each with a haptic.
            for index in badges.indices {
                try? await Task.sleep(for: .milliseconds(index == 0 ? 150 : 450))
                withAnimation(.spring(duration: 0.5, bounce: 0.5)) { shown = index + 1 }
                Haptics.success()
            }
            withAnimation(.easeOut(duration: 0.9)) { burst = true }
        }
    }
}
