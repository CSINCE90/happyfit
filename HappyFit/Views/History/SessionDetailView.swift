import SwiftUI
import SwiftData

/// Dettaglio di un allenamento concluso: modificabile in ogni parte (nome, orari, serie, esercizi).
struct SessionDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var viewModel: SessionDetailViewModel?

    @State private var correcting: SetEntry?
    @State private var editingTimes = false
    @State private var showingRename = false
    @State private var nameDraft = ""
    @State private var showingPicker = false
    @State private var showingDelete = false
    @State private var deletingSet: SetEntry?
    @State private var removingExercise: SessionExercise?

    let session: WorkoutSession

    var body: some View {
        dialogs(on: contentList)
            .task { if viewModel == nil { viewModel = SessionDetailViewModel(session: session, context: context) } }
            .onDisappear { viewModel?.performPendingDeletion() }
    }

    private var contentList: some View {
        List {
            Section {
                Button {
                    nameDraft = session.name
                    showingRename = true
                } label: {
                    row("Nome", value: session.name, icon: "pencil")
                }
                Button { editingTimes = true } label: {
                    row("Inizio", value: session.startedAt.formatted(date: .abbreviated, time: .shortened), icon: "calendar")
                }
                Button { editingTimes = true } label: {
                    row("Fine", value: (session.endedAt ?? session.startedAt).formatted(date: .abbreviated, time: .shortened), icon: "calendar")
                }
                LabeledContent("Durata", value: Formatting.duration(from: session.startedAt, to: session.endedAt ?? session.startedAt))
                LabeledContent("Serie completate", value: "\(session.completedSetCount)")
            }
            .hfListRow()

            ForEach(session.sortedExercises) { item in
                Section {
                    ForEach(Array(item.sortedSets.enumerated()), id: \.element.id) { index, entry in
                        Button { correcting = entry } label: {
                            HistorySetRow(index: index + 1, entry: entry)
                        }
                        .buttonStyle(.plain)
                        .hfListRow()
                        .swipeActions {
                            Button("Elimina", systemImage: "trash") { deletingSet = entry }
                                .tint(.red)
                        }
                    }
                    Button {
                        viewModel?.addSet(to: item)
                    } label: {
                        Label("Aggiungi serie", systemImage: "plus").font(.hfHeadline).frame(minHeight: 44)
                    }
                    .hfListRow()
                } header: {
                    HStack {
                        Text(item.exercise?.name ?? "Esercizio")
                            .font(.hfHeadline)
                            .foregroundStyle(palette.textPrimary)
                            .textCase(nil)
                        if let group = item.exercise?.muscleGroup { MuscleChip(group: group) }
                        Spacer()
                        Menu {
                            Button("Rimuovi esercizio", systemImage: "trash", role: .destructive) { removingExercise = item }
                        } label: {
                            Image(systemName: "ellipsis.circle").frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .accessibilityLabel("Azioni esercizio \(item.exercise?.name ?? "")")
                    }
                }
            }

            Section {
                Button { showingPicker = true } label: {
                    Label("Aggiungi esercizio", systemImage: "plus").font(.hfHeadline).frame(minHeight: 44)
                }
                .hfListRow()
            }
            Section {
                Button(role: .destructive) { showingDelete = true } label: {
                    Label("Elimina allenamento", systemImage: "trash")
                        .font(.hfHeadline)
                        .foregroundStyle(palette.destructive)
                        .frame(minHeight: 44)
                }
                .hfListRow()
            }
        }
        .hfScreenBackground()
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $correcting) { entry in
            SetCorrectionSheet(
                entry: entry,
                onSave: { viewModel?.updateSet(entry, weightKg: $0, reps: $1, type: $2) },
                onDelete: { deletingSet = entry }
            )
        }
        .sheet(isPresented: $editingTimes) {
            SessionTimesSheet(start: session.startedAt, end: session.endedAt ?? session.startedAt) { start, end in
                viewModel?.updateTimes(start: start, end: end) ?? false
            }
        }
        .sheet(isPresented: $showingPicker) {
            ExercisePickerView { viewModel?.addExercise($0) }
        }
    }

    private func dialogs<V: View>(on view: V) -> some View {
        view
        .alert("Rinomina allenamento", isPresented: $showingRename) {
            TextField("Nome", text: $nameDraft)
            Button("Annulla", role: .cancel) {}
            Button("Salva") { viewModel?.rename(to: nameDraft) }
        }
        .confirmationDialog("Eliminare la serie?", isPresented: Binding(get: { deletingSet != nil }, set: { if !$0 { deletingSet = nil } }), titleVisibility: .visible, presenting: deletingSet) { entry in
            Button("Elimina serie", role: .destructive) { viewModel?.removeSet(entry) }
            Button("Annulla", role: .cancel) {}
        }
        .confirmationDialog("Togliere l'esercizio dall'allenamento?", isPresented: Binding(get: { removingExercise != nil }, set: { if !$0 { removingExercise = nil } }), titleVisibility: .visible, presenting: removingExercise) { item in
            Button("Rimuovi \"\(item.exercise?.name ?? "esercizio")\"", role: .destructive) { viewModel?.removeExercise(item) }
            Button("Annulla", role: .cancel) {}
        } message: { _ in
            Text("Verranno eliminate anche le sue serie. L'esercizio resta nel catalogo.")
        }
        .confirmationDialog("Eliminare l'allenamento?", isPresented: $showingDelete, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) { deleteSession() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Verranno eliminate anche tutte le sue serie.")
        }
        .alert("Allenamento vuoto", isPresented: Binding(get: { viewModel?.offerDeletingSession ?? false }, set: { if !$0 { viewModel?.offerDeletingSession = false } })) {
            Button("Elimina allenamento", role: .destructive) { deleteSession() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Un allenamento concluso deve avere almeno una serie completata. Vuoi eliminare l'intero allenamento?")
        }
        .alert("Errore", isPresented: Binding(get: { viewModel?.errorMessage != nil }, set: { if !$0 { viewModel?.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel?.errorMessage ?? "")
        }
    }

    /// Chiude la schermata e solo dopo elimina (in onDisappear): la vista non rilegge un allenamento già cancellato.
    private func deleteSession() {
        viewModel?.requestSessionDeletion()
        dismiss()
    }

    private func row(_ title: String, value: String, icon: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.primary)
            Spacer()
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            Image(systemName: icon).foregroundStyle(.secondary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// Riga di una serie nel dettaglio: numero, peso × ripetizioni grandi, tipo con icona e parola.
private struct HistorySetRow: View {
    @Environment(\.palette) private var palette
    let index: Int
    let entry: SetEntry

    var body: some View {
        HStack(spacing: Spacing.m) {
            Text("\(index)")
                .font(.system(.subheadline, design: .rounded, weight: .heavy).monospacedDigit())
                .foregroundStyle(palette.textSecondary)
                .frame(minWidth: 24, alignment: .leading)
            Text(Formatting.setSummary(weightKg: entry.weightKg, reps: entry.reps))
                .font(.system(.title3, design: .rounded, weight: .heavy).monospacedDigit())
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: Spacing.s)
            if entry.type != .normal {
                Label {
                    Text(entry.type.displayName)
                } icon: {
                    if let symbol = entry.type.symbol { Image(systemName: symbol) }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
            }
            Image(systemName: "pencil").foregroundStyle(palette.accentText)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// Correzione di una serie: peso, ripetizioni, tipo; oppure eliminazione.
struct SetCorrectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var weightText: String
    @State private var repsText: String
    @State private var type: SetType
    let onSave: (Double, Int, SetType) -> Void
    let onDelete: (() -> Void)?

    init(entry: SetEntry, onSave: @escaping (Double, Int, SetType) -> Void, onDelete: (() -> Void)? = nil) {
        _weightText = State(initialValue: Formatting.weight(entry.weightKg))
        _repsText = State(initialValue: "\(entry.reps)")
        _type = State(initialValue: entry.type)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private var isValid: Bool { Formatting.parseNumber(weightText) != nil && Int(repsText) != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Peso", text: $weightText).keyboardType(.decimalPad).font(.hfNumber).frame(minHeight: 52)
                } header: {
                    Eyebrow("Peso (kg)")
                }
                .hfListRow()
                Section {
                    TextField("Ripetizioni", text: $repsText).keyboardType(.numberPad).font(.hfNumber).frame(minHeight: 52)
                } header: {
                    Eyebrow("Ripetizioni")
                }
                .hfListRow()
                Section {
                    // Chip da almeno 44 pt (il selettore segmentato di sistema è più basso).
                    ChipFlow(spacing: Spacing.s) {
                        ForEach(SetType.allCases, id: \.self) { option in
                            FilterChip(title: option.displayName, isOn: type == option) { type = option }
                        }
                    }
                    .padding(.vertical, Spacing.xs)
                } header: {
                    Eyebrow("Tipo di serie")
                }
                .hfListRow()
                if let onDelete {
                    Section {
                        Button("Elimina serie", systemImage: "trash", role: .destructive) {
                            dismiss()
                            onDelete()
                        }
                        .font(.hfHeadline)
                        .foregroundStyle(palette.destructive)
                        .frame(minHeight: 44)
                    }
                    .hfListRow()
                }
            }
            .hfScreenBackground()
            .navigationTitle("Correggi serie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        if let weight = Formatting.parseNumber(weightText), let reps = Int(repsText) { onSave(weight, reps, type) }
                        dismiss()
                    }
                    .bold()
                    .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// Modifica di inizio e fine: la fine non può precedere l'inizio.
struct SessionTimesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var start: Date
    @State private var end: Date
    /// Ritorna true se il salvataggio è andato a buon fine.
    let onSave: (Date, Date) -> Bool

    init(start: Date, end: Date, onSave: @escaping (Date, Date) -> Bool) {
        _start = State(initialValue: start)
        _end = State(initialValue: end)
        self.onSave = onSave
    }

    private var endsBeforeStart: Bool { end < start }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Inizio", selection: $start).frame(minHeight: 44)
                    DatePicker("Fine", selection: $end).frame(minHeight: 44)
                } header: {
                    Eyebrow("Orari")
                } footer: {
                    if endsBeforeStart {
                        Label("La fine non può precedere l'inizio.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(palette.destructive)
                    }
                }
                .hfListRow()
            }
            .hfScreenBackground()
            .navigationTitle("Data e ora")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { if onSave(start, end) { dismiss() } }
                        .bold()
                        .disabled(endsBeforeStart)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#if DEBUG
#Preview {
    let container = PreviewData.container()
    return NavigationStack { SessionDetailView(session: PreviewData.closedSession(in: container)) }
        .modelContainer(container)
}
#endif
