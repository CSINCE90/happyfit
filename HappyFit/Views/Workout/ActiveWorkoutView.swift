import SwiftUI
import SwiftData

/// Sessione di allenamento in corso.
struct ActiveWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ActiveWorkoutViewModel

    @State private var editingNumber: NumberTarget?
    @State private var editingRest: SessionExercise?
    @State private var showingPicker = false
    @State private var showingFinishDialog = false
    @State private var showingDiscardDialog = false

    init(session: WorkoutSession, context: ModelContext) {
        _viewModel = State(initialValue: ActiveWorkoutViewModel(session: session, context: context))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.session.sortedExercises) { item in
                        ExerciseCard(
                            item: item,
                            viewModel: viewModel,
                            onEditNumber: { editingNumber = $0 },
                            onEditRest: { editingRest = item }
                        )
                    }

                    Button {
                        showingPicker = true
                    } label: {
                        Label("Aggiungi esercizio", systemImage: "plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding()
            }
            .navigationTitle(viewModel.session.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Riduci") { dismiss() }
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
                Text("Le \(viewModel.incompleteSetCount) serie non completate verranno eliminate.")
            }
            .confirmationDialog("Nessuna serie completata", isPresented: $showingDiscardDialog, titleVisibility: .visible) {
                Button("Scarta allenamento", role: .destructive) { viewModel.discard() }
                Button("Continua l'allenamento", role: .cancel) {}
            } message: {
                Text("Non c'è nulla da salvare. Vuoi scartare questo allenamento?")
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

#Preview {
    let container = PreviewData.container(openSession: true)
    return ActiveWorkoutView(session: PreviewData.openSession(in: container), context: container.mainContext)
        .modelContainer(container)
}
