import SwiftUI
import SwiftData

/// Storico degli allenamenti chiusi.
struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.palette) private var palette
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt != nil }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]
    @State private var deleting: WorkoutSession?
    @State private var viewModel: HistoryViewModel?
    @State private var showingNew = false

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    ContentUnavailableView("Nessun allenamento", systemImage: "clock.arrow.circlepath", description: Text("Gli allenamenti terminati compariranno qui."))
                }
                ForEach(sessions) { session in
                    NavigationLink {
                        SessionDetailView(session: session)
                    } label: {
                        HistoryRow(session: session)
                    }
                    .hfListRow()
                    .swipeActions {
                        Button("Elimina", systemImage: "trash") { deleting = session }
                            .tint(.red)
                    }
                    .contextMenu {
                        Button("Elimina", systemImage: "trash", role: .destructive) { deleting = session }
                    }
                }
            }
            .hfScreenBackground()
            .navigationTitle("Storico")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Aggiungi allenamento", systemImage: "plus") { showingNew = true }
                }
            }
            .sheet(isPresented: $showingNew) {
                if let viewModel { PastSessionSheet(viewModel: viewModel) }
            }
            .task { if viewModel == nil { viewModel = HistoryViewModel(context: context) } }
            .confirmationDialog("Eliminare l'allenamento?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { session in
                Button("Elimina", role: .destructive) { viewModel?.delete(session) }
            } message: { _ in
                Text("Verranno eliminate anche tutte le sue serie.")
            }
            .alert("Errore", isPresented: Binding(get: { viewModel?.errorMessage != nil }, set: { if !$0 { viewModel?.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel?.errorMessage ?? "")
            }
        }
    }
}

#if DEBUG
#Preview {
    HistoryView()
        .modelContainer(PreviewData.container())
}
#endif

/// Riga dello storico: data in grande, nome, totali e gruppi muscolari.
private struct HistoryRow: View {
    @Environment(\.palette) private var palette
    let session: WorkoutSession

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            VStack(spacing: 0) {
                Text(session.startedAt.formatted(.dateTime.day()))
                    .font(.system(.title, design: .rounded, weight: .black).monospacedDigit())
                    .foregroundStyle(palette.accentText)
                Eyebrow(session.startedAt.formatted(.dateTime.month(.abbreviated)))
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(minWidth: 48)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(session.name).font(.hfHeadline).foregroundStyle(palette.textPrimary)
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline).foregroundStyle(palette.textSecondary)
                Text("\(session.exercises.count) esercizi · \(session.completedSetCount) serie · \(Formatting.duration(from: session.startedAt, to: session.endedAt ?? session.startedAt))")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                MuscleChipsView(exercises: session.sortedExercises.map(\.exercise))
            }
        }
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: 44, alignment: .leading)
    }
}
