import SwiftUI

/// Pulsante primario del Watch: accento pieno, testo scuro, alto almeno 52 pt.
struct WatchPrimaryButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.hfHeadline)
            .foregroundStyle(palette.onAccent)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, Spacing.s)
            .frame(maxWidth: .infinity, minHeight: TouchTarget.primary)
            .background(palette.accent, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Pulsante secondario del Watch: superficie rialzata, alto almeno 44 pt.
struct WatchSecondaryButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.hfHeadline)
            .foregroundStyle(palette.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, minHeight: TouchTarget.minimum)
            .background(palette.raised, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Progresso dell'esercizio: segmenti fino a 8 serie, oltre una barra continua.
struct WatchSetProgress: View {
    @Environment(\.palette) private var palette
    let completed: Int
    let total: Int

    var body: some View {
        Group {
            if total <= 8 {
                HStack(spacing: 3) {
                    ForEach(0..<max(total, 1), id: \.self) { index in
                        Capsule().fill(index < completed ? palette.accent : palette.raised)
                    }
                }
            } else {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.raised)
                        Capsule().fill(palette.accent)
                            .frame(width: proxy.size.width * CGFloat(completed) / CGFloat(max(total, 1)))
                    }
                }
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel("\(completed) di \(total) serie completate")
    }
}

/// Anello del recupero: si svuota man mano che il tempo passa.
struct WatchTimerRing: View {
    @Environment(\.palette) private var palette
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(palette.raised, lineWidth: 6)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(palette.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }
}

/// Riquadro di un valore (peso o ripetizioni): tocco per selezionarlo e cambiarlo con la Digital Crown.
struct WatchValueTile: View {
    @Environment(\.palette) private var palette
    let value: String
    let unit: String
    let label: String
    let isSelected: Bool
    let valueFont: Font
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(value)
                    .font(valueFont)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Eyebrow(unit).foregroundStyle(palette.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: TouchTarget.minimum)
            .padding(.vertical, Spacing.xs)
            .background(palette.raised, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .strokeBorder(isSelected ? palette.accent : .clear, lineWidth: 3)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) \(value) \(unit)")
        .accessibilityHint(isSelected ? "Ruota la Digital Crown per cambiarlo" : "Tocca per cambiarlo con la Digital Crown")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
