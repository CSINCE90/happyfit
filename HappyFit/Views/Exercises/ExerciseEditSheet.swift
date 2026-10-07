import SwiftUI

/// Crea o modifica un esercizio (nome, gruppo muscolare, recupero predefinito).
struct ExerciseEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let exercise: Exercise?
    let viewModel: ExerciseCatalogViewModel

    @FocusState private var nameFocused: Bool
    @State private var name: String
    @State private var group: MuscleGroup?
    @State private var customRest: Bool
    @State private var restSeconds: Int

    init(exercise: Exercise?, viewModel: ExerciseCatalogViewModel) {
        self.exercise = exercise
        self.viewModel = viewModel
        _name = State(initialValue: exercise?.name ?? "")
        _group = State(initialValue: exercise?.muscleGroup)
        _customRest = State(initialValue: exercise?.defaultRestSeconds != nil)
        _restSeconds = State(initialValue: exercise?.defaultRestSeconds ?? AppSettings.defaultRestSeconds())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nome") {
                    TextField("Nome esercizio", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .focused($nameFocused)
                }
                Section("Gruppo muscolare") {
                    Picker("Gruppo", selection: $group) {
                        Text("Nessuno").tag(MuscleGroup?.none)
                        ForEach(MuscleGroup.allCases, id: \.self) { Text($0.displayName).tag(MuscleGroup?.some($0)) }
                    }
                }
                Section {
                    Toggle("Recupero personalizzato", isOn: $customRest)
                    if customRest {
                        Stepper(value: $restSeconds, in: 0...900, step: 15) {
                            Text(Formatting.rest(restSeconds))
                        }
                    }
                } footer: {
                    Text("Se spento si usa il recupero predefinito delle Impostazioni.")
                }
                if let message = viewModel.errorMessage {
                    Section { Text(message).foregroundStyle(.red) }
                }
            }
            .navigationTitle(exercise == nil ? "Nuovo" : "Modifica")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { viewModel.errorMessage = nil; dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva", action: save).bold()
                }
            }
            .onAppear {
                viewModel.errorMessage = nil
                // Nuovo esercizio: si scrive subito il nome.
                if exercise == nil { nameFocused = true }
            }
        }
    }

    private func save() {
        let rest = customRest ? restSeconds : nil
        let ok: Bool
        if let exercise {
            ok = viewModel.update(exercise, name: name, group: group, defaultRestSeconds: rest)
        } else {
            ok = viewModel.create(name: name, group: group, defaultRestSeconds: rest)
        }
        if ok { dismiss() }
    }
}

#if DEBUG
#Preview("Nuovo") {
    let container = PreviewData.container()
    return ExerciseEditSheet(exercise: nil, viewModel: ExerciseCatalogViewModel(context: container.mainContext))
        .modelContainer(container)
}
#endif

#if DEBUG
#Preview("Modifica") {
    let container = PreviewData.container()
    return ExerciseEditSheet(exercise: PreviewData.exercise(in: container), viewModel: ExerciseCatalogViewModel(context: container.mainContext))
        .modelContainer(container)
}
#endif
