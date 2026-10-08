import SwiftUI

/// Pulsante primario: accento pieno, testo scuro, alto almeno 52 pt.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.hfHeadline)
            .foregroundStyle(palette.onAccent)
            .padding(.horizontal, Spacing.l)
            .frame(minHeight: TouchTarget.primary)
            .frame(maxWidth: .infinity)
            .background(palette.accent, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .strokeBorder(palette.accentOutline, lineWidth: 1.5)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
    }
}

/// Pulsante secondario: contorno d'accento su superficie, alto almeno 44 pt.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.hfHeadline)
            .foregroundStyle(palette.accentText)
            .padding(.horizontal, Spacing.m)
            .frame(minHeight: TouchTarget.minimum)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(palette.raised, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .strokeBorder(palette.accentText.opacity(0.6), lineWidth: 1.5)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}

/// Pulsante tondo − / + dei valori: superficie rialzata, area di tocco 48 × 48 pt.
struct StepCircleButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .black))
            .foregroundStyle(palette.textPrimary)
            .frame(width: 48, height: 48)
            .background(palette.raised, in: Circle())
            .contentShape(Circle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.35)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var hfPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var hfSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    static var hfSecondaryWide: SecondaryButtonStyle { SecondaryButtonStyle(fullWidth: true) }
}

extension ButtonStyle where Self == StepCircleButtonStyle {
    static var hfStep: StepCircleButtonStyle { StepCircleButtonStyle() }
}
