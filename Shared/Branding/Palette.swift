import SwiftUI

// Token di colore di HappyFit. Solo SwiftUI (niente UIKit): compila anche per watchOS.
// Valori verificati: testo su sfondo ≥ 4.5:1 (WCAG) in ogni coppia usata; colori di categorie diverse
// (accento, semantici, gruppi muscolari) distanti almeno ΔE2000 ≈ 20 tra loro nello stesso tema.

extension Color {
    /// Colore da valore esadecimale 0xRRGGBB.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Colore d'accento scelto dall'utente.
enum AccentPreset: String, CaseIterable, Identifiable, Sendable {
    case volt, arancio, rosa, viola, blu, ciano

    static let `default`: AccentPreset = .volt

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .volt: return "Volt"
        case .arancio: return "Arancio"
        case .rosa: return "Rosa"
        case .viola: return "Viola"
        case .blu: return "Blu"
        case .ciano: return "Ciano"
        }
    }

    /// Colore pieno (pulsanti, cerchi, segmenti): sempre con testo `Palette.ink` sopra.
    var fill: Color {
        switch self {
        case .volt: return Color(hex: 0xC6FF00)
        case .arancio: return Color(hex: 0xFF8A1F)
        case .rosa: return Color(hex: 0xFF5CD1)
        case .viola: return Color(hex: 0xA97BFF)
        case .blu: return Color(hex: 0x4D8DFF)
        case .ciano: return Color(hex: 0x22D3EE)
        }
    }

    /// Variante scura usata come colore del testo nel tema chiaro.
    var textOnLight: Color {
        switch self {
        case .volt: return Color(hex: 0x3F6212)
        case .arancio: return Color(hex: 0x8A5700)
        case .rosa: return Color(hex: 0xB0177F)
        case .viola: return Color(hex: 0x6D28D9)
        case .blu: return Color(hex: 0x1D4ED8)
        case .ciano: return Color(hex: 0x0B6475)
        }
    }
}

/// Aspetto scelto in Impostazioni.
enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "Sistema"
        case .light: return "Chiaro"
        case .dark: return "Scuro"
        }
    }

    /// nil = segue l'impostazione del sistema.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Tutti i colori di una schermata, risolti per tema e accento.
struct Palette: Sendable {
    let isDark: Bool
    let accentPreset: AccentPreset

    /// Testo scuro da usare sopra i colori pieni (accento, semantici, gruppi nel tema chiaro).
    static let ink = Color(hex: 0x0B0D10)

    var background: Color { isDark ? Color(hex: 0x0B0D10) : Color(hex: 0xF2F3F5) }
    var card: Color { isDark ? Color(hex: 0x171A1F) : Color(hex: 0xFFFFFF) }
    var raised: Color { isDark ? Color(hex: 0x22262D) : Color(hex: 0xE7E9ED) }
    var separator: Color { isDark ? Color(hex: 0x2C313A) : Color(hex: 0xD5D9E0) }
    var textPrimary: Color { isDark ? Color(hex: 0xF5F7FA) : Color(hex: 0x0B0D10) }
    var textSecondary: Color { isDark ? Color(hex: 0xA3ACB9) : Color(hex: 0x4B5563) }

    /// Accento pieno (con `ink` sopra).
    var accent: Color { accentPreset.fill }
    /// Accento usato come colore di testo o icona su card e sfondo.
    var accentText: Color { isDark ? accentPreset.fill : accentPreset.textOnLight }
    /// Bordo delle forme piene d'accento: nel tema chiaro i colori vivaci su bianco hanno poco contrasto
    /// di forma, quindi si contornano con la variante scura (nel tema scuro non serve).
    var accentOutline: Color { isDark ? .clear : accentPreset.textOnLight }
    /// Testo sopra l'accento pieno.
    var onAccent: Color { Self.ink }

    /// Serie completata, esito positivo (pieno, con `ink` sopra).
    var success: Color { Color(hex: 0x30D158) }
    /// Avviso (pieno, con `ink` sopra).
    var warning: Color { Color(hex: 0xFFD60A) }
    /// Azioni distruttive come testo o icona (sempre insieme a icona e parola).
    var destructive: Color { isDark ? Color(hex: 0xFF6961) : Color(hex: 0xC41E1E) }

    /// Riempimento del chip di un gruppo muscolare.
    func muscleFill(_ group: MuscleGroup) -> Color {
        if isDark {
            switch group {
            case .petto: return Color(hex: 0xB4123F)
            case .schiena: return Color(hex: 0x1E40AF)
            case .gambe: return Color(hex: 0x15803D)
            case .spalle: return Color(hex: 0x9A4A0B)
            case .braccia: return Color(hex: 0x8E1B8A)
            case .core: return Color(hex: 0x0E6B73)
            }
        } else {
            switch group {
            case .petto: return Color(hex: 0xCC958F)
            case .schiena: return Color(hex: 0xD9EEFF)
            case .gambe: return Color(hex: 0xC4CCA3)
            case .spalle: return Color(hex: 0xFFE8D9)
            case .braccia: return Color(hex: 0xECD0F5)
            case .core: return Color(hex: 0x78F0D2)
            }
        }
    }

    /// Testo sopra il chip di un gruppo muscolare.
    var onMuscle: Color { isDark ? .white : Self.ink }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette(isDark: true, accentPreset: .default)
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// Inserisce la palette nell'ambiente, ricalcolata a ogni cambio di tema o accento.
struct HappyFitTheme: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let accent: AccentPreset

    func body(content: Content) -> some View {
        let palette = Palette(isDark: colorScheme == .dark, accentPreset: accent)
        content
            .environment(\.palette, palette)
            .tint(palette.accentText)
    }
}

extension View {
    func happyFitTheme(accent: AccentPreset) -> some View {
        modifier(HappyFitTheme(accent: accent))
    }
}
