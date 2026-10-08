import SwiftUI
import SwiftData

/// Sessione di allenamento in corso.
struct ActiveWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var viewModel: ActiveWorkoutViewModel

    @State private var editingNumber: NumberTarget?
    @State private var editingRest: SessionExercise?
    @State private var showingPicker = false
    @State private var showingFinishDialog = false
    @State private var showingDiscardDialog = false
    @State private var showingDiscardAnyway = false
    @State private var showingRename = false
    @State private var nameDraft = ""

    init(session: WorkoutSession, context: ModelContext) {
        _viewModel = State(initialValue: ActiveWorkoutViewModel(session: session, context: context))
    }

    #if DEBUG
    /// Solo collaudo: usa un ViewModel già preparato (es. con il timer attivo).
    init(viewModel: ActiveWorkoutViewModel) {
        _viewModel = State(initialValue: viewModel)
    }
    #endif

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: Spacing.l) {
                    // "In corso" = il primo esercizio con almeno una serie incompleta (derivato qui, non nel ViewModel).
                    let currentID = viewModel.session.sortedExercises.first { $0.sets.contains { !$0.isCompleted } }?.id
                    ForEach(viewModel.session.sortedExercises) { item in
                        ExerciseCard(
                            item: item,
                            isCurrent: item.id == currentID,
                            viewModel: viewModel,
                            onEditNumber: { editingNumber = $0 },
                            onEditRest: { editingRest = item }
                        )
                    }

                    Button {
                        showingPicker = true
                    } label: {
                        Label("Aggiungi esercizio", systemImage: "plus")
                    }
                    .buttonStyle(.hfSecondaryWide)
                }
                .padding()
            }
            .background(palette.background)
            .navigationTitle(viewModel.session.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Riduci") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Rinomina allenamento", systemImage: "pencil") {
                            nameDraft = viewModel.session.name
                            showingRename = true
                        }
                        Button("Scarta allenamento", systemImage: "trash", role: .destructive) {
                            showingDiscardAnyway = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Altre azioni")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Termina", action: requestFinish)
                        .bold()
                }
            }
            .safeAreaInset(edge: .bottom) {
                if viewModel.restTimer != nil {
                    RestTimerBar(viewModel: viewModel)
                }
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView { viewModel.addExercise($0) }
            }
            .sheet(item: $editingNumber) { target in
                NumberEntrySheet(target: target) { value in
                    if target.isWeight {
                        viewModel.setWeight(target.entry, value)
                    } else {
                        viewModel.setReps(target.entry, Int(value))
                    }
                }
            }
            .sheet(item: $editingRest) { item in
                RestEditSheet(seconds: item.restSeconds) { viewModel.setRest(item, seconds: $0) }
            }
            .confirmationDialog(finishTitle, isPresented: $showingFinishDialog, titleVisibility: .visible) {
                Button("Termina e salva", role: .destructive) { viewModel.finish() }
                Button("Continua l'allenamento", role: .cancel) {}
            } message: {
                Text(viewModel.incompleteSetCount == 1
                     ? "La serie non completata verrà eliminata."
                     : "Le \(viewModel.incompleteSetCount) serie non completate verranno eliminate.")
            }
            .confirmationDialog("Nessuna serie completata", isPresented: $showingDiscardDialog, titleVisibility: .visible) {
                Button("Scarta allenamento", role: .destructive) { viewModel.discard() }
                Button("Continua l'allenamento", role: .cancel) {}
            } message: {
                Text("Non c'è nulla da salvare. Vuoi scartare questo allenamento?")
            }
            .confirmationDialog("Scartare l'allenamento?", isPresented: $showingDiscardAnyway, titleVisibility: .visible) {
                Button("Scarta allenamento", role: .destructive) { viewModel.discard() }
                Button("Continua l'allenamento", role: .cancel) {}
            } message: {
                Text("Verranno eliminate tutte le serie registrate, anche quelle completate. Non si può annullare.")
            }
            .alert("Rinomina allenamento", isPresented: $showingRename) {
                TextField("Nome", text: $nameDraft)
                Button("Annulla", role: .cancel) {}
                Button("Salva") { viewModel.rename(to: nameDraft) }
            }
            .alert("Errore", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .onChange(of: viewModel.didEnd) { _, ended in
                if ended { dismiss() }
            }
        }
        .interactiveDismissDisabled()
    }

    private var finishTitle: String {
        "Terminare l'allenamento?"
    }

    private func requestFinish() {
        if viewModel.canDiscard {
            showingDiscardDialog = true
        } else if viewModel.incompleteSetCount > 0 {
            showingFinishDialog = true
        } else {
            viewModel.finish()
        }
    }
}

/// Serie e campo da modificare con il tastierino.
struct NumberTarget: Identifiable {
    let id = UUID()
    let entry: SetEntry
    let isWeight: Bool
}

#if DEBUG
#Preview {
    let container = PreviewData.container(openSession: true)
    return ActiveWorkoutView(session: PreviewData.openSession(in: container), context: container.mainContext)
        .modelContainer(container)
}
#endif
