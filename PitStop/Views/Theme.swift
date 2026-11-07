import SwiftUI
import UIKit

/// PitStop's palette: bright and energetic, with tuned light/dark variants.
///
/// | Token  | Used for                                              |
/// |--------|-------------------------------------------------------|
/// | coral  | Brand accent, partner pins, planned route             |
/// | lime   | Completed path, success, "My Places" stamps          |
/// | sky    | You (user marker), recommended places                 |
/// | sun    | "New" badges, rewards, crossing alerts                |
/// | muted  | Real places not on PitStop yet                        |
enum Theme {
    /// Matches the AccentColor asset so `.tint` and `Theme.coral` always agree.
    static let coral = Color.accentColor
    static let coralDeep = dynamic(light: (0.90, 0.24, 0.10), dark: (1.00, 0.36, 0.20))
    static let lime = dynamic(light: (0.40, 0.74, 0.06), dark: (0.62, 0.95, 0.25))
    static let sky = dynamic(light: (0.08, 0.56, 0.98), dark: (0.36, 0.72, 1.00))
    static let sun = dynamic(light: (1.00, 0.74, 0.02), dark: (1.00, 0.84, 0.26))
    static let muted = dynamic(light: (0.55, 0.57, 0.62), dark: (0.60, 0.62, 0.68))

    /// Planned route: coral fading into sun.
    static let routeGradient: [Color] = [coralDeep, coral, sun]
    /// Path already covered.
    static let completedGradient: [Color] = [lime, lime.opacity(0.85)]

    /// Builds a color that switches automatically between light and dark mode.
    private static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}
