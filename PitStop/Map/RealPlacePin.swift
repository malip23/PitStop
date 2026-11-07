import SwiftUI

/// Map annotation for a REAL place.
///
/// - Default: a small muted dot ("Not on PitStop yet"), so partner pins stand out
/// - Selected: grows to show its category icon
/// - Recommended: sky blue with a star
/// - Visited (in My Places): lime checkmark stamp
struct RealPlacePin: View {
    let place: RealPlace
    var status = PinStatus()

    var body: some View {
        Group {
            if status.isRecommended || status.isSelected || status.isDestination || status.matchLabel != nil {
                expanded
            } else {
                dot
            }
        }
        .animation(.spring(duration: 0.3), value: status)
    }

    private var dot: some View {
        Circle()
            .fill(status.isVisited ? Theme.lime : Theme.muted.opacity(0.75))
            .frame(width: 11, height: 11)
            .overlay(Circle().stroke(.white, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.15), radius: 1)
            .overlay(alignment: .topTrailing) {
                if status.isVisited { PinBadge.visited.scaleEffect(0.7).offset(x: 9, y: -9) }
            }
            .padding(8) // bigger tap target
            .contentShape(Circle())
    }

    private var expanded: some View {
        let tint = status.isRecommended ? Theme.sky : (status.matchLabel != nil ? Theme.coral : Theme.muted)
        return Image(systemName: place.category.symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(status.isRecommended ? .white : .secondary)
            .frame(width: 32, height: 32)
            .background(status.isRecommended ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(.thinMaterial), in: Circle())
            .overlay(Circle().stroke(status.isRecommended ? .white : tint.opacity(status.matchLabel != nil ? 1 : 0.4),
                                     lineWidth: status.isRecommended || status.matchLabel != nil ? 2.5 : 1))
            .overlay(alignment: .bottom) {
                if let label = status.matchLabel { MatchLabel(text: label).offset(y: 20) }
            }
            .overlay(alignment: .topLeading) {
                if status.isRecommended { PinBadge.recommended.offset(x: -6, y: -6) }
            }
            .overlay(alignment: .topTrailing) {
                if status.isDestination { PinBadge.destination.offset(x: 7, y: -7) }
                else if status.isVisited { PinBadge.visited.offset(x: 6, y: -6) }
            }
    }
}
