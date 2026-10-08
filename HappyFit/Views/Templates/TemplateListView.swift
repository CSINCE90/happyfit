import SwiftUI
import SwiftData

/// Lista delle schede: crea, rinomina, duplica, riordina, elimina.
struct TemplateListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.palette) private var palette
    @Query(sort: \WorkoutTemplate.order) private var templates: [WorkoutTemplate]
    @State private var viewModel: TemplatesViewModel?

    @State private var nameDraft = ""
    @State private var editMode: EditMode = .inactive
    @State private var showingNew = false
    @State private var renaming: WorkoutTemplate?
    @State private var deleting: WorkoutTemplate?

    var body: some View {
        NavigationStack {
            List {
                if templates.isEmpty {
                    ContentUnavailableView("Nessuna scheda", systemImage: "list.bullet.rectangle", description: Text("Tocca + per creare la tua prima scheda."))
                }
                ForEach(templates) { template in
                    NavigationLink {
                        TemplateEditorView(template: template)
                    } label: {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(template.name).font(.hfTitle).foregroundStyle(palette.textPrimary)
                            Text("\(template.exercises.count) esercizi").font(.subheadline).foregroundStyle(palette.textSecondary)
                            MuscleChipsView(exercises: template.sortedExercises.map(\.exercise))
                        }
                        .padding(.vertical, Spacing.xs)
                        .padding(.trailing, 48)
                        .frame(minHeight: 44, alignment: .leading)
                    }
                    // Menu sempre visibile su ogni scheda (oltre a swipe e tocco prolungato).
                    .overlay(alignment: .trailing) {
                        Menu {
                            Button("Rinomina", systemImage: "pencil") { nameDraft = template.name; renaming = template }
                            Button("Duplica", systemImage: "plus.square.on.square") { viewModel?.duplicate(template) }
                            Button("Elimina", systemImage: "trash", role: .destructive) { deleting = template }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                                .foregroundStyle(palette.accentText)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .padding(.trailing, 20)
                        .accessibilityLabel("Azioni scheda \(template.name)")
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Elimina", systemImage: "trash") { deleting = template }
                            .tint(.red)
                        Button("Duplica", systemImage: "plus.square.on.square") { viewModel?.duplicate(template) }
                            .tint(.blue)
                    }
                    .contextMenu {
                        Button("Rinomina", systemImage: "pencil") { nameDraft = template.name; renaming = template }
                        Button("Duplica", systemImage: "plus.square.on.square") { viewModel?.duplicate(template) }
                        Button("Elimina", systemImage: "trash", role: .destructive) { deleting = template }
                    }
                }
                .onMove { viewModel?.move(templates, from: $0, to: $1) }
                .hfListRow()
            }
            .hfScreenBackground()
            .navigationTitle("Schede")
            .environment(\.editMode, $editMode)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(editMode.isEditing ? "Fine" : "Riordina") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                    .frame(minHeight: 44)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Nuova scheda", systemImage: "plus") { nameDraft = ""; showingNew = true }
                }
            }
            .alert("Nuova scheda", isPresented: $showingNew) {
                TextField("Nome", text: $nameDraft)
                Button("Annulla", role: .cancel) {}
                Button("Crea") { viewModel?.create(name: nameDraft) }
            }
            .alert("Rinomina scheda", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Nome", text: $nameDraft)
                Button("Annulla", role: .cancel) {}
                Button("Salva") { if let renaming { viewModel?.rename(renaming, to: nameDraft) } }
            }
            .confirmationDialog("Eliminare la scheda?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { template in
                Button("Elimina \"\(template.name)\"", role: .destructive) { viewModel?.delete(template) }
            } message: { _ in
                Text("Gli allenamenti già svolti restano nello storico.")
            }
            .alert("Errore", isPresented: Binding(get: { viewModel?.errorMessage != nil }, set: { if !$0 { viewModel?.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel?.errorMessage ?? "")
            }
            .task { if viewModel == nil { viewModel = TemplatesViewModel(context: context) } }
        }
    }
}

#if DEBUG
#Preview {
    TemplateListView()
        .modelContainer(PreviewData.container())
}
#endif

#if DEBUG
#Preview("Vuota") {
    TemplateListView()
        .modelContainer(try! PersistenceController.makeContainer(inMemory: true))
}
#endif
