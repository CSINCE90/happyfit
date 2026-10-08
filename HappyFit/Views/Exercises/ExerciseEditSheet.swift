import SwiftUI

/// Crea o modifica un esercizio (nome, gruppo muscolare, recupero predefinito).
struct ExerciseEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

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
                Section {
                    TextField("Nome esercizio", text: $name)
                        .font(.hfHeadline)
                        .textInputAutocapitalization(.sentences)
                        .focused($nameFocused)
                        .frame(minHeight: 44)
                } header: {
                    Eyebrow("Nome")
                }
                .hfListRow()
                Section {
                    Picker("Gruppo", selection: $group) {
                        Text("Nessuno").tag(MuscleGroup?.none)
                        ForEach(MuscleGroup.allCases, id: \.self) { Text($0.displayName).tag(MuscleGroup?.some($0)) }
                    }
                    .frame(minHeight: 44)
                } header: {
                    Eyebrow("Gruppo muscolare")
                }
                .hfListRow()
                Section {
                    Toggle("Recupero personalizzato", isOn: $customRest)
                        .tint(palette.accent)
                        .frame(minHeight: 44)
                    if customRest {
                        HStack(spacing: Spacing.m) {
                            Text(Formatting.rest(restSeconds))
                                .font(.system(.title3, design: .rounded, weight: .heavy).monospacedDigit())
                                .foregroundStyle(palette.textPrimary)
                            Spacer(minLength: Spacing.s)
                            StepButton(systemImage: "minus", label: "Recupero meno", isEnabled: restSeconds > 0) {
                                restSeconds = max(restSeconds - 15, 0)
                            }
                            StepButton(systemImage: "plus", label: "Recupero più", isEnabled: restSeconds < 900) {
                                restSeconds = min(restSeconds + 15, 900)
                            }
                        }
                    }
                } footer: {
                    Text("Se spento si usa il recupero predefinito delle Impostazioni.")
                }
                .hfListRow()
                if let exercise {
                    Section {
                        Button("Archivia esercizio", systemImage: "archivebox") {
                            viewModel.archive(exercise)
                            dismiss()
                        }
                        .font(.hfHeadline)
                        .foregroundStyle(palette.textPrimary)
                        .frame(minHeight: 44)
                        Button("Elimina esercizio", systemImage: "trash", role: .destructive) {
                            viewModel.requestDelete(exercise)
                        }
                        .font(.hfHeadline)
                        .foregroundStyle(palette.destructive)
                        .frame(minHeight: 44)
                    } footer: {
                        Text("Un esercizio già usato in un allenamento non si elimina: si archivia e resta nello storico.")
                    }
                    .hfListRow()
                }
                if let message = viewModel.errorMessage {
                    Section { Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(palette.destructive) }
                        .hfListRow()
                }
            }
            .hfScreenBackground()
            .exerciseDeletionDialogs(viewModel) { dismiss() }
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
