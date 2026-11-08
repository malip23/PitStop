import Foundation
import Observation

/// Developer/demo switches, persisted in UserDefaults.
@Observable
final class DeveloperSettings {
    /// Play back runs along the chosen route instead of using real GPS.
    var demoMode: Bool { didSet { save() } }
    /// Playback speed multiplier for Demo Mode (1× = real pace).
    var demoSpeed: Double { didSet { save() } }
    /// Turn off anti-cheat (e.g. when simulating locations from Xcode during a demo).
    var antiCheatEnabled: Bool { didSet { save() } }

    private let defaults = UserDefaults.standard

    init() {
        demoMode = defaults.bool(forKey: "dev.demoMode")
        let speed = defaults.double(forKey: "dev.demoSpeed")
        demoSpeed = speed > 0 ? speed : 3
        defaults.register(defaults: ["dev.antiCheat": true])
        antiCheatEnabled = defaults.bool(forKey: "dev.antiCheat")
    }

    private func save() {
        defaults.set(demoMode, forKey: "dev.demoMode")
        defaults.set(demoSpeed, forKey: "dev.demoSpeed")
        defaults.set(antiCheatEnabled, forKey: "dev.antiCheat")
    }
}
