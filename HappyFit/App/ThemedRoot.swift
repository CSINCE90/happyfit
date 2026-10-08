import SwiftUI

/// Applica aspetto (Sistema / Chiaro / Scuro) e colore d'accento scelti in Impostazioni a tutta l'app.
struct ThemedRoot<Content: View>: View {
    @AppStorage(AppSettings.accentKey) private var accentRaw = AccentPreset.default.rawValue
    @AppStorage(AppSettings.appearanceKey) private var appearanceRaw = AppearancePreference.system.rawValue
    @ViewBuilder let content: Content

    var body: some View {
        content
            .happyFitTheme(accent: AccentPreset(rawValue: accentRaw) ?? .default)
            .preferredColorScheme((AppearancePreference(rawValue: appearanceRaw) ?? .system).colorScheme)
    }
}
