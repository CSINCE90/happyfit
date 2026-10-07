import SwiftUI
import SwiftData

/// Dettaglio di un allenamento chiuso, con correzione di peso e ripetizioni.
struct SessionDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var correcting: SetEntry?
    @State private var showingDelete = false
    @State private var errorMessage: String?

    let session: WorkoutSession

    var body: some View {
        List {
            Section {
                LabeledContent("Inizio", value: session.startedAt.formatted(date: .abbreviated, time: .shortened))
                if let end = session.endedAt {
                    LabeledContent("Durata", value: Formatting.duration(from: session.startedAt, to: end))
                }
                LabeledContent("Serie completate", value: "\(session.completedSetCount)")
            }
            ForEach(session.sortedExercises) { item in
                Section(item.exercise?.name ?? "Esercizio") {
                    ForEach(Array(item.sortedSets.enumerated()), id: \.element.id) { index, entry in
                        Button {
                            correcting = entry
                        } label: {
                            HStack {
                                Text("\(index + 1)").foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
                                Text(Formatting.setSummary(weightKg: entry.weightKg, reps: entry.reps))
                                    .font(.body.monospacedDigit())
                                Spacer()
                                if entry.type != .normal {
                                    Text(entry.type.displayName).font(.caption).foregroundStyle(entry.type.color)
                                }
                                Image(systemName: "pencil").foregroundStyle(.secondary)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Section {
                Button("Elimina allenamento", role: .destructive) { showingDelete = true }
                    .frame(minHeight: 44)
            }
        }
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $correcting) { entry in
            SetCorrectionSheet(entry: entry) { weight, reps in
                do { try WorkoutService(context: context).updateSet(entry, weightKg: weight, reps: reps) } catch { errorMessage = error.localizedDescription }
            }
        }
        .confirmationDialog("Eliminare l'allenamento?", isPresented: $showingDelete, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                do {
                    try WorkoutService(context: context).deleteSession(session)
                    dismiss()
                } catch { errorMessage = error.localizedDescription }
            }
        }
        .alert("Errore", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

/// Correzione di peso e ripetizioni di una serie.
struct SetCorrectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var weightText: String
    @State private var repsText: String
    let onSave: (Double, Int) -> Void

    init(entry: SetEntry, onSave: @escaping (Double, Int) -> Void) {
        _weightText = State(initialValue: Formatting.weight(entry.weightKg))
        _repsText = State(initialValue: "\(entry.reps)")
        self.onSave = onSave
    }

    private var isValid: Bool { Formatting.parseNumber(weightText) != nil && Int(repsText) != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Peso (kg)") {
                    TextField("Peso", text: $weightText).keyboardType(.decimalPad).font(.title2.monospacedDigit())
                }
                Section("Ripetizioni") {
                    TextField("Ripetizioni", text: $repsText).keyboardType(.numberPad).font(.title2.monospacedDigit())
                }
            }
            .navigationTitle("Correggi serie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        if let weight = Formatting.parseNumber(weightText), let reps = Int(repsText) { onSave(weight, reps) }
                        dismiss()
                    }
                    .bold()
                    .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    let container = PreviewData.container()
    return NavigationStack { SessionDetailView(session: PreviewData.closedSession(in: container)) }
        .modelContainer(container)
}
