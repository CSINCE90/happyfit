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
                            Button("Elimina", systemImage: "trash") { viewModel.requestDelete(exercise) }
                                .tint(.red)
                            Button("Archivia", systemImage: "archivebox") { viewModel.archive(exercise) }
                                .tint(.orange)
                        }
                        .contextMenu {
                            Button("Modifica", systemImage: "pencil") { editing = exercise }
                            Button("Archivia", systemImage: "archivebox") { viewModel.archive(exercise) }
                            Button("Elimina", systemImage: "trash", role: .destructive) { viewModel.requestDelete(exercise) }
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
                .exerciseDeletionDialogs(viewModel)
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

/// Esercizi archiviati: si possono ripristinare o, se mai usati, eliminare.
struct ArchivedExercisesView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Exercise> { $0.isArchived }, sort: \Exercise.name) private var archived: [Exercise]
    @State private var viewModel: ExerciseCatalogViewModel?

    var body: some View {
        List {
            if archived.isEmpty {
                Text("Nessun esercizio archiviato.").foregroundStyle(.secondary)
            }
            ForEach(archived) { exercise in
                HStack {
                    ExerciseRow(exercise: exercise)
                    Button("Ripristina") { viewModel?.unarchive(exercise) }
                        .buttonStyle(.bordered)
                }
                .frame(minHeight: 44)
                .swipeActions {
                    Button("Elimina", systemImage: "trash") { viewModel?.requestDelete(exercise) }
                        .tint(.red)
                }
                .contextMenu {
                    Button("Ripristina", systemImage: "arrow.uturn.backward") { viewModel?.unarchive(exercise) }
                    Button("Elimina", systemImage: "trash", role: .destructive) { viewModel?.requestDelete(exercise) }
                }
            }
        }
        .navigationTitle("Archiviati")
        .task { if viewModel == nil { viewModel = ExerciseCatalogViewModel(context: context) } }
        .modifier(OptionalDeletionDialogs(viewModel: viewModel))
    }
}

/// Applica le finestre di eliminazione quando il ViewModel è pronto.
private struct OptionalDeletionDialogs: ViewModifier {
    let viewModel: ExerciseCatalogViewModel?

    func body(content: Content) -> some View {
        if let viewModel {
            content.exerciseDeletionDialogs(viewModel)
        } else {
            content
        }
    }
}

#if DEBUG
#Preview("Catalogo") {
    NavigationStack { ExerciseCatalogView() }
        .modelContainer(PreviewData.container())
}
#endif

#if DEBUG
#Preview("Archiviati") {
    let container = PreviewData.container()
    try? WorkoutService(context: container.mainContext).archiveExercise(PreviewData.exercise(in: container))
    return NavigationStack { ArchivedExercisesView() }
        .modelContainer(container)
}
#endif
