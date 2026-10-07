import SwiftUI

/// Barra del timer di recupero, fissa in basso durante l'allenamento.
/// Due righe (tempo, poi pulsanti) e Dynamic Type limitato, così non occupa mai più di circa un quinto dello schermo.
struct RestTimerBar: View {
    let viewModel: ActiveWorkoutViewModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Formatting.clock(viewModel.restRemainingSeconds))
                    .font(.title.monospacedDigit().bold())
                    .lineLimit(1)
                Text("Recupero")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }

    private func buttons(compact: Bool) -> some View {
        HStack(spacing: 10) {
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
        .frame(maxWidth: .infinity, minHeight: 44)
        if prominent {
            Button(action: action) { content }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(label)
        } else {
            Button(action: action) { content }
                .buttonStyle(.bordered)
                .accessibilityLabel(label)
        }
    }
}

/// Modifica al volo del recupero di un esercizio (vale solo per questa sessione).
struct RestEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var seconds: Int
    let onSave: (Int) -> Void

    init(seconds: Int, onSave: @escaping (Int) -> Void) {
        _seconds = State(initialValue: seconds)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $seconds, in: 0...900, step: 15) {
                        Text(Formatting.rest(seconds)).font(.title2.monospacedDigit())
                    }
                } footer: {
                    Text("La modifica vale solo per questo allenamento.")
                }
            }
            .navigationTitle("Recupero")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { onSave(seconds); dismiss() }.bold()
                }
            }
        }
        .presentationDetents([.medium])
    }
}
