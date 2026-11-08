import SwiftUI

/// Slim top pill (about 56–64 pt): icon + one line. Tap to expand details; swipe up to dismiss.
struct PopupPill<Details: View>: View {
    let symbol: String
    let tint: Color
    /// Foreground on the tinted icon circle.
    var iconForeground: Color = .white
    let text: String
    var trailing: String? = nil
    let onDismiss: () -> Void
    @ViewBuilder var details: Details

    @State private var expanded = false
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(iconForeground)
                    .frame(width: 34, height: 34)
                    .background(tint, in: Circle())
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(expanded ? 3 : 1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if let trailing {
                    Text(trailing)
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            if expanded {
                details
                    .font(.subheadline)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(minHeight: 56)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(tint.opacity(0.5), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .offset(y: min(dragOffset, 0))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { dragOffset = $0.translation.height }
                .onEnded { value in
                    if value.translation.height < -30 { onDismiss() }
                    withAnimation(.snappy) { dragOffset = 0 }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Dismiss", onDismiss)
    }
}
