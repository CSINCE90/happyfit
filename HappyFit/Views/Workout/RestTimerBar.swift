import SwiftUI

/// Barra del timer di recupero, fissa in basso. È l'unico elemento in vetro (Liquid Glass su iOS 26, materiale
/// traslucido prima); i pulsanti dentro sono pieni, mai vetro su vetro. Due righe e Dynamic Type limitato,
/// così resta sotto circa un quinto dell'altezza dello schermo; con testo molto grande l'anello si nasconde.
struct RestTimerBar: View {
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let viewModel: ActiveWorkoutViewModel

    private var progress: Double {
        guard let total = viewModel.restTimer?.totalSeconds, total > 0 else { return 0 }
        return Double(viewModel.restRemainingSeconds) / Double(total)
    }

    var body: some View {
        VStack(spacing: Spacing.s) {
            HStack(alignment: .center, spacing: Spacing.m) {
                if !typeSize.isAccessibilitySize {
                    TimerRing(progress: progress)
                        .frame(width: 34, height: 34)
                }
                Text(Formatting.clock(viewModel.restRemainingSeconds))
                    .font(.hfTimer)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Eyebrow("Recupero")
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            // Testo se c'è spazio, altrimenti solo icone: i pulsanti non vanno mai a capo.
            ViewThatFits(in: .horizontal) {
                buttons(compact: false)
                buttons(compact: true)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .frame(maxWidth: .infinity)
        .modifier(GlassBarBackground())
        // Stesso margine laterale delle card della sessione (16 pt), così anello e "Salta" non toccano il bordo.
        .padding(.horizontal, Spacing.l)
        .padding(.bottom, Spacing.xs)
    }

    private func buttons(compact: Bool) -> some View {
        HStack(spacing: Spacing.s) {
            barButton(compact ? nil : "−15 s", icon: "gobackward.15", label: "Meno 15 secondi") {
                viewModel.addRest(seconds: -15)
            }
            barButton(compact ? nil : "+15 s", icon: "goforward.15", label: "Più 15 secondi") {
                viewModel.addRest(seconds: 15)
            }
            barButton(compact ? nil : "Salta", icon: "forward.end.fill", label: "Salta recupero", prominent: true) {
                viewModel.skipRest()
            }
        }
    }

    @ViewBuilder
    private func barButton(_ title: String?, icon: String, label: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        let content = Group {
            if let title {
                Text(title).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            } else {
                Image(systemName: icon)
            }
        }
        .frame(maxWidth: .infinity)
        if prominent {
            Button(action: action) { content }
                .buttonStyle(.hfPrimary)
                .accessibilityLabel(label)
        } else {
            Button(action: action) { content }
                .buttonStyle(.hfSecondaryWide)
                .accessibilityLabel(label)
        }
    }
}

/// Sfondo in vetro della barra: Liquid Glass su iOS 26, materiale traslucido sulle versioni precedenti.
private struct GlassBarBackground: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

/// Modifica al volo del recupero di un esercizio (vale solo per questa sessione).
struct RestEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State var seconds: Int
    let onSave: (Int) -> Void

    init(seconds: Int, onSave: @escaping (Int) -> Void) {
        _seconds = State(initialValue: seconds)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.l) {
                VStack(spacing: Spacing.m) {
                    Eyebrow("Recupero").foregroundStyle(palette.textSecondary)
                    HStack(spacing: Spacing.l) {
                        StepButton(systemImage: "minus", label: "Recupero meno", isEnabled: seconds > 0) {
                            seconds = max(seconds - 15, 0)
                        }
                        Text(Formatting.rest(seconds))
                            .font(.hfNumber)
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity)
                        StepButton(systemImage: "plus", label: "Recupero più", isEnabled: seconds < 900) {
                            seconds = min(seconds + 15, 900)
                        }
                    }
                }
                .hfCard(padding: Spacing.l)
                Text("La modifica vale solo per questo allenamento.")
                    .font(.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .frame(maxHeight: .infinity, alignment: .top)
            .background(palette.background)
            .navigationTitle("Recupero")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { onSave(seconds); dismiss() }.bold()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
