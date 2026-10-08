import SwiftUI
import SwiftData

/// Scheda "Allenamento": riprendi la sessione aperta, avvia da una scheda o libera.
struct WorkoutHomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutTemplate.order) private var templates: [WorkoutTemplate]
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt == nil }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var openSessions: [WorkoutSession]

    @Environment(\.palette) private var palette
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
                            HStack(spacing: Spacing.m) {
                                Image(systemName: "play.fill")
                                    .font(.title2.weight(.black))
                                    .frame(width: 52, height: 52)
                                    .background(Palette.ink.opacity(0.12), in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Allenamento in corso").font(.hfTitle)
                                    Text("\(open.name) · iniziato alle \(open.startedAt.formatted(date: .omitted, time: .shortened))")
                                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                }
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(palette.onAccent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, Spacing.s)
                        }
                        .listRowBackground(palette.accent)
                    }
                }

                Section {
                    if templates.isEmpty {
                        Text("Nessuna scheda. Creane una dalla scheda \"Schede\" oppure inizia una sessione libera.")
                            .foregroundStyle(palette.textSecondary)
                            .hfListRow()
                    }
                    ForEach(templates) { template in
                        Button {
                            start { try WorkoutService(context: context).startSession(from: template) }
                        } label: {
                            HStack(alignment: .center, spacing: Spacing.m) {
                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    Text(template.name).font(.hfTitle).foregroundStyle(palette.textPrimary)
                                    Text(Formatting.count(template.exercises.count, "esercizio", "esercizi"))
                                        .font(.subheadline).foregroundStyle(palette.textSecondary)
                                    MuscleChipsView(exercises: template.sortedExercises.map(\.exercise))
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "play.fill")
                                    .font(.title3.weight(.black))
                                    .foregroundStyle(palette.onAccent)
                                    .frame(width: 48, height: 48)
                                    .background(palette.accent, in: Circle())
                                    .overlay(Circle().strokeBorder(palette.accentOutline, lineWidth: 1.5))
                            }
                            .padding(.vertical, Spacing.s)
                            .contentShape(Rectangle())
                            .opacity(openSessions.isEmpty ? 1 : 0.4)
                        }
                        .disabled(!openSessions.isEmpty)
                        .hfListRow()
                    }
                } header: {
                    Eyebrow("Da una scheda").foregroundStyle(palette.textSecondary)
                }

                Section {
                    Button {
                        start { try WorkoutService(context: context).startEmptySession(name: "Allenamento libero") }
                    } label: {
                        Label("Sessione libera", systemImage: "plus.circle.fill")
                            .font(.hfHeadline)
                            .padding(.vertical, Spacing.s)
                            // Stesso aspetto "spento" delle card delle schede quando c'è una sessione aperta.
                            .foregroundStyle(openSessions.isEmpty ? palette.accentText : palette.textSecondary)
                            .opacity(openSessions.isEmpty ? 1 : 0.6)
                    }
                    .disabled(!openSessions.isEmpty)
                    .hfListRow()
                } footer: {
                    if !openSessions.isEmpty {
                        Text("Termina o scarta l'allenamento in corso prima di iniziarne un altro.")
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            .hfScreenBackground()
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

#if DEBUG
#Preview("Con allenamento aperto") {
    WorkoutHomeView()
        .modelContainer(PreviewData.container(openSession: true))
}
#endif

#if DEBUG
#Preview("Senza sessione") {
    WorkoutHomeView()
        .modelContainer(PreviewData.container())
}
#endif
