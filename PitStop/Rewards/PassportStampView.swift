import SwiftUI

/// An ink-style passport stamp. The shape, color, and icon come from the place's category, and
/// each stamp gets a slight, stable tilt (from its id) so the collection looks hand-stamped.
struct PassportStampView: View {
    let name: String
    let category: BusinessCategory
    let date: Date
    let seed: String
    var size: CGFloat = 104

    var body: some View {
        let style = StampStyle(category: category)
        ZStack {
            style.shape
                .fill(style.color.opacity(0.10))
            style.shape
                .stroke(style.color, style: StrokeStyle(lineWidth: 2.5, dash: style.dashed ? [5, 3] : []))
                .padding(4)
            style.shape
                .stroke(style.color.opacity(0.6), lineWidth: 1)
                .padding(9)

            VStack(spacing: 2) {
                Text("PITSTOP")
                    .font(.system(size: size * 0.075, weight: .heavy, design: .rounded))
                    .tracking(1.5)
                Image(systemName: category.symbol)
                    .font(.system(size: size * 0.26, weight: .bold))
                Text(name.uppercased())
                    .font(.system(size: size * 0.08, weight: .heavy, design: .rounded))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, size * 0.14)
                Text(date.formatted(.dateTime.month(.abbreviated).day().year(.twoDigits)).uppercased())
                    .font(.system(size: size * 0.07, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(style.color)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(tilt))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stamp: \(name), \(category.displayName), \(date.formatted(date: .abbreviated, time: .omitted))")
    }

    /// Stable −8°…+8° tilt from the id.
    private var tilt: Double {
        let sum = seed.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Double(sum % 17) - 8
    }
}

/// Per-category stamp design.
struct StampStyle {
    let color: Color
    let shape: AnyShape
    let dashed: Bool

    init(category: BusinessCategory) {
        switch category {
        case .cafe:
            color = Theme.coralDeep; shape = AnyShape(Circle()); dashed = false
        case .bakery:
            color = Color.brown; shape = AnyShape(RoundedRectangle(cornerRadius: 22, style: .continuous)); dashed = true
        case .juicery, .smoothieBar:
            color = Theme.lime; shape = AnyShape(Circle()); dashed = true
        case .restaurant:
            color = Theme.coral; shape = AnyShape(RoundedRectangle(cornerRadius: 10)); dashed = false
        case .fitness, .yogaStudio:
            color = Theme.sky; shape = AnyShape(Capsule()); dashed = false
        case .store, .bookstore:
            color = Color.indigo; shape = AnyShape(RoundedRectangle(cornerRadius: 4)); dashed = true
        case .bikeShop:
            color = Color.teal; shape = AnyShape(Circle()); dashed = false
        case .gelato:
            color = Color.pink; shape = AnyShape(Ellipse()); dashed = true
        case .other:
            color = Theme.muted; shape = AnyShape(RoundedRectangle(cornerRadius: 16)); dashed = true
        }
    }
}
