import SwiftUI
import SwiftData

/// Catalogo esercizi: ricerca, filtro, crea, modifica, archivia.
struct ExerciseCatalogView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var viewModel: ExerciseCatalogViewModel?
    @State private var editing: Exercise?
    @State private var showingNew = false

    var body: some View {
        Group {
            if let viewModel {
                List {
                    GroupFilterView(selected: Binding(get: { viewModel.selectedGroup }, set: { viewModel.selectedGroup = $0 }))
                    let visible = viewModel.visible(from: exercises)
                    if visible.isEmpty {
                        Text("Nessun esercizio trovato.").foregroundStyle(.secondary)
                    }
                    ForEach(visible) { exercise in
                        Button { editing = exercise } label: {
                            ExerciseRow(exercise: exercise)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Archivia", systemImage: "archivebox") { viewModel.archive(exercise) }
                                .tint(.orange)
                        }
                    }
                    Section {
                        NavigationLink("Esercizi archiviati (\(viewModel.archived(from: exercises).count))") {
                            ArchivedExercisesView()
                        }
                    }
                }
                .searchable(text: Binding(get: { viewModel.searchText }, set: { viewModel.searchText = $0 }), prompt: "Cerca esercizio")
                .sheet(isPresented: $showingNew) { ExerciseEditSheet(exercise: nil, viewModel: viewModel) }
                .sheet(item: $editing) { ExerciseEditSheet(exercise: $0, viewModel: viewModel) }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Esercizi")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Nuovo", systemImage: "plus") { showingNew = true }
            }
        }
        .task { if viewModel == nil { viewModel = ExerciseCatalogViewModel(context: context) } }
    }
}

/// Esercizi archiviati: si possono ripristinare.
struct ArchivedExercisesView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Exercise> { $0.isArchived }, sort: \Exercise.name) private var archived: [Exercise]

    var body: some View {
        List {
            if archived.isEmpty {
                Text("Nessun esercizio archiviato.").foregroundStyle(.secondary)
            }
            ForEach(archived) { exercise in
                HStack {
                    ExerciseRow(exercise: exercise)
                    Button("Ripristina") {
                        try? WorkoutService(context: context).unarchiveExercise(exercise)
                    }
                    .buttonStyle(.bordered)
                }
                .frame(minHeight: 44)
            }
        }
        .navigationTitle("Archiviati")
    }
}

#Preview("Catalogo") {
    NavigationStack { ExerciseCatalogView() }
        .modelContainer(PreviewData.container())
}

#Preview("Archiviati") {
    let container = PreviewData.container()
    try? WorkoutService(context: container.mainContext).archiveExercise(PreviewData.exercise(in: container))
    return NavigationStack { ArchivedExercisesView() }
        .modelContainer(container)
}
