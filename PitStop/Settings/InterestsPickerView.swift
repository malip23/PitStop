import SwiftUI

/// Multi-select grid of interests. Used in Settings (and onboarding later).
struct InterestsPickerView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pick what you love passing or visiting. PitStop's AI uses this to choose scenic routes and suggest places.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                InterestGrid()
            }
            .padding()
        }
        .navigationTitle("Interests")
    }
}

/// The tappable chips themselves, reusable anywhere.
struct InterestGrid: View {
    @Environment(AppState.self) private var app

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
            ForEach(Interest.allCases) { interest in
                let selected = app.preferences.interests.contains(interest)
                Button {
                    if selected { app.preferences.interests.remove(interest) } else { app.preferences.interests.insert(interest) }
                } label: {
                    Label(interest.displayName, systemImage: interest.symbol)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .foregroundStyle(selected ? .white : .primary)
                        .background(selected ? AnyShapeStyle(Theme.coral.gradient) : AnyShapeStyle(Color(.secondarySystemBackground)),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: selected)
            }
        }
    }
}
