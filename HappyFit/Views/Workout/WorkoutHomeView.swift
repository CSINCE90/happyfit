import SwiftUI
import SwiftData

/// Scheda "Allenamento": riprendi la sessione aperta, avvia da una scheda o libera.
struct WorkoutHomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutTemplate.order) private var templates: [WorkoutTemplate]
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt == nil }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var openSessions: [WorkoutSession]

    @State private var presented: WorkoutSession?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let open = openSessions.first {
                    Section {
                        Button {
                            presented = open
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "play.circle.fill").font(.title)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Allenamento in corso").font(.headline)
                                    Text("\(open.name) · iniziato alle \(open.startedAt.formatted(date: .omitted, time: .shortened))")
                                        .font(.subheadline)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                        }
                        .listRowBackground(Color.accentColor.opacity(0.18))
                    }
                }

                Section("Da una scheda") {
                    if templates.isEmpty {
                        Text("Nessuna scheda. Creane una dalla scheda \"Schede\" oppure inizia una sessione libera.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(templates) { template in
                        Button {
                            start { try WorkoutService(context: context).startSession(from: template) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name).font(.headline)
                                    Text("\(template.exercises.count) esercizi")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "play.fill")
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .disabled(!openSessions.isEmpty)
                    }
                }

                Section {
                    Button {
                        start { try WorkoutService(context: context).startEmptySession(name: "Allenamento libero") }
                    } label: {
                        Label("Sessione libera", systemImage: "plus.circle")
                            .font(.headline)
                            .padding(.vertical, 6)
                            // Stesso aspetto "spento" delle card delle schede quando c'è una sessione aperta.
                            .foregroundStyle(openSessions.isEmpty ? Color.accentColor : Color.secondary.opacity(0.6))
                    }
                    .disabled(!openSessions.isEmpty)
                } footer: {
                    if !openSessions.isEmpty {
                        Text("Termina o scarta l'allenamento in corso prima di iniziarne un altro.")
                    }
                }
            }
            .navigationTitle("Allenamento")
            .alert("Errore", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .fullScreenCover(item: $presented) { session in
                ActiveWorkoutView(session: session, context: context)
            }
        }
    }

    private func start(_ work: () throws -> WorkoutSession) {
        do {
            presented = try work()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview("Con allenamento aperto") {
    WorkoutHomeView()
        .modelContainer(PreviewData.container(openSession: true))
}

#Preview("Senza sessione") {
    WorkoutHomeView()
        .modelContainer(PreviewData.container())
}
