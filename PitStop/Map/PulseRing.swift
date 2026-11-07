import SwiftUI

/// An expanding, fading ring that loops forever: the "glowing pulse" behind live pins and the user dot.
struct PulseRing: View {
    var color: Color
    var size: CGFloat
    var scale: CGFloat = 1.9
    var duration: Double = 1.6

    @State private var animate = false

    var body: some View {
        Circle()
            .fill(color.opacity(0.45))
            .frame(width: size, height: size)
            .scaleEffect(animate ? scale : 1)
            .opacity(animate ? 0 : 0.9)
            .onAppear {
                withAnimation(.easeOut(duration: duration).repeatForever(autoreverses: false)) {
                    animate = true
                }
            }
            .allowsHitTesting(false)
    }
}
