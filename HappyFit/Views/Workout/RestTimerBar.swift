import SwiftUI

/// Barra del timer di recupero, fissa in basso durante l'allenamento.
struct RestTimerBar: View {
    let viewModel: ActiveWorkoutViewModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Recupero").font(.caption).foregroundStyle(.secondary)
                Text(Formatting.clock(viewModel.restRemainingSeconds))
                    .font(.largeTitle.monospacedDigit().bold())
            }
            Spacer()
            Button("−15 s") { viewModel.addRest(seconds: -15) }
                .buttonStyle(.bordered)
            Button("+15 s") { viewModel.addRest(seconds: 15) }
                .buttonStyle(.bordered)
            Button("Salta") { viewModel.skipRest() }
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
        .padding()
        .background(.regularMaterial)
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
