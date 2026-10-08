import SwiftUI

/// Registra a posteriori un allenamento già fatto (poi si completa dal dettaglio).
struct PastSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let viewModel: HistoryViewModel

    @State private var name = ""
    @State private var start = Date().addingTimeInterval(-3_600)
    @State private var end = Date()
    @State private var exercise: Exercise?
    @State private var weightText = "0"
    @State private var repsText = "0"
    @State private var showingPicker = false

    private var endsBeforeStart: Bool { end < start }
    private var isValid: Bool {
        exercise != nil && !endsBeforeStart && Formatting.parseNumber(weightText) != nil && Int(repsText) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Allenamento", text: $name).font(.hfHeadline).frame(minHeight: 44)
                } header: {
                    Eyebrow("Nome")
                }
                .hfListRow()
                Section {
                    DatePicker("Inizio", selection: $start).frame(minHeight: 44)
                    DatePicker("Fine", selection: $end).frame(minHeight: 44)
                    if endsBeforeStart {
                        Label("La fine non può precedere l'inizio.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(palette.destructive)
                    }
                } header: {
                    Eyebrow("Orari")
                }
                .hfListRow()
                Section {
                    Button {
                        showingPicker = true
                    } label: {
                        HStack {
                            Text("Esercizio").foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text(exercise?.name ?? "Scegli…").font(.hfHeadline).foregroundStyle(palette.accentText)
                        }
                        .frame(minHeight: 44)
                    }
                    TextField("Peso (kg)", text: $weightText).keyboardType(.decimalPad).font(.hfHeadline.monospacedDigit()).frame(minHeight: 44)
                    TextField("Ripetizioni", text: $repsText).keyboardType(.numberPad).font(.hfHeadline.monospacedDigit()).frame(minHeight: 44)
                } header: {
                    Eyebrow("Prima serie")
                } footer: {
                    Text("Un allenamento concluso ha almeno una serie completata. Le altre le aggiungi dal dettaglio.")
                }
                .hfListRow()
                if let message = viewModel.errorMessage {
                    Section { Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(palette.destructive) }
                        .hfListRow()
                }
            }
            .hfScreenBackground()
            .navigationTitle("Nuovo allenamento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { viewModel.errorMessage = nil; dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva", action: save).bold().disabled(!isValid)
                }
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView { exercise = $0 }
            }
            .onAppear { viewModel.errorMessage = nil }
        }
    }

    private func save() {
        guard let exercise, let weight = Formatting.parseNumber(weightText), let reps = Int(repsText) else { return }
        if viewModel.createPast(name: name, startedAt: start, endedAt: end, exercise: exercise, weightKg: weight, reps: reps) != nil {
            dismiss()
        }
    }
}
