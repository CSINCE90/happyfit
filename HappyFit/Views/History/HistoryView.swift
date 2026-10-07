import SwiftUI
import SwiftData

/// Storico degli allenamenti chiusi.
struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt != nil }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]
    @State private var deleting: WorkoutSession?
    @State private var errorMessage: String?

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
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.name).font(.headline)
                            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text("\(session.exercises.count) esercizi · \(session.completedSetCount) serie · \(Formatting.duration(from: session.startedAt, to: session.endedAt ?? session.startedAt))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 44, alignment: .leading)
                    }
                    .swipeActions {
                        Button("Elimina", systemImage: "trash", role: .destructive) { deleting = session }
                    }
                }
            }
            .navigationTitle("Storico")
            .confirmationDialog("Eliminare l'allenamento?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { session in
                Button("Elimina", role: .destructive) {
                    do { try WorkoutService(context: context).deleteSession(session) } catch { errorMessage = error.localizedDescription }
                }
            } message: { _ in
                Text("Verranno eliminate anche tutte le sue serie.")
            }
            .alert("Errore", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
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
