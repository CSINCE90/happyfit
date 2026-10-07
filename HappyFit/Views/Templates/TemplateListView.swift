import SwiftUI
import SwiftData

/// Lista delle schede: crea, rinomina, duplica, riordina, elimina.
struct TemplateListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutTemplate.order) private var templates: [WorkoutTemplate]
    @State private var viewModel: TemplatesViewModel?

    @State private var nameDraft = ""
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
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name).font(.headline)
                            Text("\(template.exercises.count) esercizi").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 44, alignment: .leading)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Elimina", systemImage: "trash", role: .destructive) { deleting = template }
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
            }
            .navigationTitle("Schede")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
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

#Preview {
    TemplateListView()
        .modelContainer(PreviewData.container())
}

#Preview("Vuota") {
    TemplateListView()
        .modelContainer(try! PersistenceController.makeContainer(inMemory: true))
}
