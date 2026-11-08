import SwiftUI

/// The shareable run card (rendered to a 1080×1350 image). Designed at 360×450 points, rendered @3x.
struct ShareCardView: View {
    let mapImage: UIImage?
    let distance: String
    let duration: String
    let pace: String
    let activityName: String
    let destinationName: String?
    let reward: (text: String, business: String)?
    let stamp: (name: String, category: BusinessCategory, date: Date, id: String)?
    let verified: Bool
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Map with the route.
            ZStack(alignment: .topLeading) {
                Group {
                    if let mapImage {
                        Image(uiImage: mapImage).resizable().scaledToFill()
                    } else {
                        LinearGradient(colors: [Theme.coralDeep.opacity(0.6), .black], startPoint: .top, endPoint: .bottom)
                    }
                }
                .frame(width: 336, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                HStack(spacing: 5) {
                    Image(systemName: "mappin.and.ellipse")
                    Text("PitStop").fontWeight(.heavy)
                }
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Theme.coral, in: Capsule())
                .padding(10)
            }

            // Headline.
            VStack(alignment: .leading, spacing: 2) {
                Text("\(distance) \(activityName.lowercased())")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                if let destinationName {
                    Text("to \(destinationName)").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
            }

            HStack(spacing: 18) {
                stat(duration, "Time")
                stat(pace, "Pace")
                Spacer()
                if verified {
                    Label("Verified", systemImage: "checkmark.shield.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.lime)
                }
            }

            HStack(alignment: .center, spacing: 12) {
                if let reward {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("REWARD UNLOCKED", systemImage: "gift.fill")
                            .font(.system(size: 9, weight: .heavy))
                            .opacity(0.7)
                        Text(reward.text).font(.system(size: 15, weight: .bold)).lineLimit(2)
                        Text("at \(reward.business)").font(.system(size: 11)).opacity(0.7).lineLimit(1)
                    }
                    .foregroundStyle(.black.opacity(0.85))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.sun, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    Text("Run somewhere worth it.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let stamp {
                    PassportStampView(name: stamp.name, category: stamp.category, date: stamp.date, seed: stamp.id, size: 86)
                        .colorScheme(.dark)
                }
            }

            Spacer(minLength: 0)
            Text(date.formatted(date: .long, time: .omitted))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(12)
        .frame(width: 360, height: 450, alignment: .topLeading)
        .foregroundStyle(.white)
        .background(
            LinearGradient(colors: [Color(red: 0.13, green: 0.09, blue: 0.10), Color(red: 0.05, green: 0.05, blue: 0.07)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.6))
        }
    }
}
