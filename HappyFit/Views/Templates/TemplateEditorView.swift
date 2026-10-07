import SwiftUI
import SwiftData

/// Editor di una scheda: esercizi con serie, ripetizioni e recupero target.
struct TemplateEditorView: View {
    @Environment(\.modelContext) private var context
    @State private var viewModel: TemplatesViewModel?
    @State private var showingPicker = false
    @State private var showingRename = false
    @State private var nameDraft = ""
    @State private var editMode: EditMode = .inactive

    let template: WorkoutTemplate

    var body: some View {
        List {
            if template.exercises.isEmpty {
                Text("Nessun esercizio: aggiungine uno.").foregroundStyle(.secondary)
            }
            ForEach(template.sortedExercises) { row in
                TemplateRowEditor(row: row) { sets, reps, rest in
                    viewModel?.update(row, sets: sets, reps: reps, restSeconds: rest)
                }
            }
            .onDelete { viewModel?.removeExercises(of: template, at: $0) }
            .onMove { viewModel?.moveExercises(of: template, from: $0, to: $1) }

            Section {
                Button {
                    showingPicker = true
                } label: {
                    Label("Aggiungi esercizio", systemImage: "plus")
                        .font(.headline)
                        .frame(minHeight: 44)
                }
            }
        }
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Rinomina scheda", systemImage: "pencil") { nameDraft = template.name; showingRename = true }
                    Button(editMode.isEditing ? "Fine riordino" : "Riordina esercizi",
                           systemImage: "arrow.up.arrow.down") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Altre azioni")
            }
        }
        .environment(\.editMode, $editMode)
        .sheet(isPresented: $showingPicker) {
            ExercisePickerView { viewModel?.addExercise($0, to: template) }
        }
        .alert("Rinomina scheda", isPresented: $showingRename) {
            TextField("Nome", text: $nameDraft)
            Button("Annulla", role: .cancel) {}
            Button("Salva") { viewModel?.rename(template, to: nameDraft) }
        }
        .alert("Errore", isPresented: Binding(get: { viewModel?.errorMessage != nil }, set: { if !$0 { viewModel?.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel?.errorMessage ?? "")
        }
        .task { if viewModel == nil { viewModel = TemplatesViewModel(context: context) } }
    }
}

/// Riga dell'editor: nome esercizio e tre valori, ciascuno su una riga (etichetta a sinistra, − valore + a destra).
private struct TemplateRowEditor: View {
    let row: TemplateExercise
    let onChange: (Int?, Int?, Int?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.exercise?.name ?? "Esercizio").font(.headline)
            ValueRow(label: "Serie", valueText: "\(row.targetSets)", range: 1...20, value: row.targetSets, step: 1) {
                onChange($0, nil, nil)
            }
            ValueRow(label: "Ripetizioni", valueText: "\(row.targetReps)", range: 1...100, value: row.targetReps, step: 1) {
                onChange(nil, $0, nil)
            }
            ValueRow(label: "Recupero", valueText: Formatting.rest(row.restSeconds), range: 0...900, value: row.restSeconds, step: 15) {
                onChange(nil, nil, $0)
            }
        }
        .padding(.vertical, 6)
    }
}

/// Riga etichetta + − valore +, alta almeno 48 pt; con testo molto grande va su due righe.
private struct ValueRow: View {
    let label: String
    let valueText: String
    let range: ClosedRange<Int>
    let value: Int
    let step: Int
    let onChange: (Int) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Text(label).lineLimit(1)
                Spacer(minLength: 8)
                controls(valueMinWidth: 72)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                controls(valueMinWidth: 0)
            }
        }
        .frame(minHeight: 48)
        .padding(.vertical, 2)
    }

    private func controls(valueMinWidth: CGFloat) -> some View {
        HStack(spacing: 8) {
            StepButton(systemImage: "minus", label: "\(label) meno", isEnabled: value > range.lowerBound) {
                onChange(max(value - step, range.lowerBound))
            }
            Text(valueText)
                .font(.body.monospacedDigit().bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(minWidth: valueMinWidth, maxWidth: valueMinWidth == 0 ? .infinity : nil)
            StepButton(systemImage: "plus", label: "\(label) più", isEnabled: value < range.upperBound) {
                onChange(min(value + step, range.upperBound))
            }
        }
    }
}

#if DEBUG
#Preview {
    let container = PreviewData.container()
    return NavigationStack { TemplateEditorView(template: PreviewData.template(in: container)) }
        .modelContainer(container)
}
#endif
