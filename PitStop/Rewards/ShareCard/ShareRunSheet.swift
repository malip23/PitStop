import SwiftUI

/// Preview + share for a run card. "Hide start and finish" is on by default for privacy.
struct ShareRunSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let run: RunRecord

    @State private var image: UIImage?
    @State private var hideEnds = true
    @State private var isRendering = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ZStack {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
                                .accessibilityLabel("Run card preview")
                        } else {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.secondary.opacity(0.12))
                                .aspectRatio(4 / 5, contentMode: .fit)
                        }
                        if isRendering { ProgressView() }
                    }
                    .frame(maxWidth: 340)

                    Toggle(isOn: $hideEnds) {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Hide start and finish")
                                Text("Trims ~200 m so your home stays private").font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "eye.slash.fill")
                        }
                    }
                    .tint(Theme.coral)
                    .padding(.horizontal, 4)

                    if let image {
                        ShareLink(item: Image(uiImage: image),
                                  message: Text(shareMessage),
                                  preview: SharePreview("My PitStop run", image: Image(uiImage: image))) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
                .padding()
            }
            .navigationTitle("Share run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .task(id: hideEnds) { await render() }
        }
    }

    private var shareMessage: String {
        var text = "Just ran \(Format.distance(run.distanceMeters))"
        if let name = run.destinationName { text += " to \(name)" }
        return text + " with PitStop 🏃"
    }

    private func render() async {
        isRendering = true
        image = await RunShareRenderer.image(for: run, stamp: app.history.stamp(forRun: run.id),
                                             reward: app.history.reward(forRun: run.id), hideEnds: hideEnds)
        isRendering = false
    }
}
