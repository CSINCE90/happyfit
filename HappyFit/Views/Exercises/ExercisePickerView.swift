import SwiftUI
import SwiftData

/// Selettore di esercizio dal catalogo (per sessioni e schede), con ricerca, filtro e creazione al volo.
struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var viewModel: ExerciseCatalogViewModel?
    @State private var showingNew = false

    let onSelect: (Exercise) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    List {
                        GroupFilterView(selected: Binding(get: { viewModel.selectedGroup }, set: { viewModel.selectedGroup = $0 }))
                        ForEach(viewModel.visible(from: exercises)) { exercise in
                            Button {
                                onSelect(exercise)
                                dismiss()
                            } label: {
                                ExerciseRow(exercise: exercise)
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .searchable(text: Binding(get: { viewModel.searchText }, set: { viewModel.searchText = $0 }), prompt: "Cerca esercizio")
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Scegli esercizio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Nuovo", systemImage: "plus") { showingNew = true }
                }
            }
            .sheet(isPresented: $showingNew) {
                if let viewModel { ExerciseEditSheet(exercise: nil, viewModel: viewModel) }
            }
            .task { if viewModel == nil { viewModel = ExerciseCatalogViewModel(context: context) } }
        }
    }
}

/// Riga di un esercizio: nome e gruppo muscolare.
struct ExerciseRow: View {
    let exercise: Exercise

    var body: some View {
        HStack {
            Text(exercise.name)
            Spacer()
            if let group = exercise.muscleGroup {
                Text(group.displayName).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Filtro per gruppo muscolare a scorrimento orizzontale.
struct GroupFilterView: View {
    @Binding var selected: MuscleGroup?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                chip("Tutti", isOn: selected == nil) { selected = nil }
                ForEach(MuscleGroup.allCases, id: \.self) { group in
                    chip(group.displayName, isOn: selected == group) { selected = group }
                }
            }
            .padding(.horizontal)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .tint(isOn ? .accentColor : .secondary)
            .controlSize(.regular)
    }
}

#Preview {
    ExercisePickerView { _ in }
        .modelContainer(PreviewData.container())
}
