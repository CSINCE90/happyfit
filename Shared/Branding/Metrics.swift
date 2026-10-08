import SwiftUI

/// Spaziature (multipli di 4).
enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}

/// Raggi degli angoli.
enum Radius {
    static let small: CGFloat = 12
    static let card: CGFloat = 20
    static let large: CGFloat = 28
}

/// Dimensioni minime delle aree di tocco.
enum TouchTarget {
    static let minimum: CGFloat = 44
    static let primary: CGFloat = 52
}

/// Stili tipografici: solo SF (anche arrotondato), sempre con Dynamic Type.
extension Font {
    /// Titoli marcati.
    static let hfTitle = Font.system(.title2, design: .rounded, weight: .heavy)
    static let hfHeadline = Font.system(.headline, design: .rounded, weight: .bold)
    /// Numeri grandi (peso, ripetizioni) a cifre di larghezza fissa.
    static let hfNumber = Font.system(.title, design: .rounded, weight: .black).monospacedDigit()
    /// Timer del recupero.
    static let hfTimer = Font.system(.largeTitle, design: .rounded, weight: .black).monospacedDigit()
    /// Etichette brevi in maiuscoletto (vedi `hfEyebrow`).
    static let hfEyebrow = Font.system(.caption, design: .rounded, weight: .bold)
}

/// Etichetta in maiuscoletto spaziato. `.textCase` cambierebbe anche l'etichetta di accessibilità,
/// quindi l'elemento viene ricreato con la stringa originale: VoiceOver e test di interfaccia restano uguali.
struct Eyebrow: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.hfEyebrow)
            .tracking(1)
            .textCase(.uppercase)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isStaticText)
    }
}
