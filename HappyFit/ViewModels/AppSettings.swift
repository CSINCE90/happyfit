import Foundation

/// Chiavi e valori predefiniti delle impostazioni (@AppStorage nelle viste, UserDefaults nei ViewModel).
enum AppSettings {
    static let defaultRestKey = "defaultRestSeconds"
    static let weightStepKey = "weightStepKg"
    static let accentKey = "accentPreset"
    static let appearanceKey = "appearance"

    static let defaultRestFallback = WorkoutService.fallbackRestSeconds
    static let weightStepFallback = 2.5

    static func defaultRestSeconds(_ defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: defaultRestKey) == nil ? defaultRestFallback : defaults.integer(forKey: defaultRestKey)
    }

    static func weightStep(_ defaults: UserDefaults = .standard) -> Double {
        let value = defaults.double(forKey: weightStepKey)
        return value > 0 ? value : weightStepFallback
    }
}
