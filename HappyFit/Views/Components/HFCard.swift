import SwiftUI

/// Card a superficie piena (mai vetro), con filetto d'accento a sinistra quando è "in corso".
struct HFCardModifier: ViewModifier {
    @Environment(\.palette) private var palette
    var highlighted = false
    var padding: CGFloat = Spacing.m

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(palette.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(alignment: .leading) {
                if highlighted {
                    Capsule()
                        .fill(palette.accent)
                        .frame(width: 5)
                        .padding(.vertical, Spacing.l)
                        .accessibilityHidden(true)
                }
            }
    }
}

extension View {
    func hfCard(highlighted: Bool = false, padding: CGFloat = Spacing.m) -> some View {
        modifier(HFCardModifier(highlighted: highlighted, padding: padding))
    }

    /// Righe di una List sulle superfici del tema.
    func hfListRow() -> some View {
        modifier(HFListRowModifier())
    }

    /// Sfondo del tema per List e Form.
    func hfScreenBackground() -> some View {
        modifier(HFScreenBackgroundModifier())
    }
}

private struct HFListRowModifier: ViewModifier {
    @Environment(\.palette) private var palette
    func body(content: Content) -> some View {
        content.listRowBackground(palette.card)
    }
}

private struct HFScreenBackgroundModifier: ViewModifier {
    @Environment(\.palette) private var palette
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(palette.background)
    }
}
