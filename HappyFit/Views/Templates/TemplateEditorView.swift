import SwiftUI
import SwiftData

/// Editor di una scheda: esercizi con serie, ripetizioni e recupero target.
struct TemplateEditorView: View {
    @Environment(\.modelContext) private var context
    @State private var viewModel: TemplatesViewModel?
    @State private var showingPicker = false
    @State private var showingRename = false
    @State private var nameDraft = ""

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
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Rinomina", systemImage: "pencil") { nameDraft = template.name; showingRename = true }
                EditButton()
            }
        }
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

/// Riga dell'editor: nome esercizio e tre stepper.
private struct TemplateRowEditor: View {
    let row: TemplateExercise
    let onChange: (Int?, Int?, Int?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(row.exercise?.name ?? "Esercizio").font(.headline)
            Stepper(value: Binding(get: { row.targetSets }, set: { onChange($0, nil, nil) }), in: 1...20) {
                Text("Serie: \(row.targetSets)")
            }
            Stepper(value: Binding(get: { row.targetReps }, set: { onChange(nil, $0, nil) }), in: 1...100) {
                Text("Ripetizioni: \(row.targetReps)")
            }
            Stepper(value: Binding(get: { row.restSeconds }, set: { onChange(nil, nil, $0) }), in: 0...900, step: 15) {
                Text("Recupero: \(Formatting.rest(row.restSeconds))")
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let container = PreviewData.container()
    return NavigationStack { TemplateEditorView(template: PreviewData.template(in: container)) }
        .modelContainer(container)
}
